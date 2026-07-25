import Foundation

enum CoreLogicSmokeError: LocalizedError {
    case unexpectedPath(String)
    case translationPolicy
    case missingRemoteFile(String)
    case typography
    case audioLevel

    var errorDescription: String? {
        switch self {
        case .unexpectedPath(let path):
            "Unexpected model path: \(path)"
        case .translationPolicy:
            "Live translation policy produced an invalid result."
        case .missingRemoteFile(let file):
            "Hugging Face manifest is missing: \(file)"
        case .typography:
            "Transcript typography is inconsistent."
        case .audioLevel:
            "Audio level meter produced an invalid result."
        }
    }
}

@main
struct CoreLogicSmoke {
    static func main() async throws {
        guard Defaults.defaultASRPath.hasSuffix(
            "/Documents/AI Models/animaslabs:nemotron-speech-streaming-en-0.6b-mlx-8bit"
        ) else {
            throw CoreLogicSmokeError.unexpectedPath(Defaults.defaultASRPath)
        }
        guard Defaults.defaultNMTPath.hasSuffix(
            "/Documents/AI Models/Helsinki-NLP:opus-mt-en-zh"
        ) else {
            throw CoreLogicSmokeError.unexpectedPath(Defaults.defaultNMTPath)
        }

        var policy = LiveTranslationPolicy()
        policy.setEnabled(false, at: 10)
        policy.setEnabled(true, at: 20)
        guard policy.allowsTranslation(for: 9),
              !policy.allowsTranslation(for: 15),
              policy.allowsTranslation(for: 21) else {
            throw CoreLogicSmokeError.translationPolicy
        }

        guard TranscriptTypography.sourceSize(for: 24) == 19.68,
              TranscriptTypography.translationSize(for: 24) == 22.56 else {
            throw CoreLogicSmokeError.typography
        }

        let silence = Data(count: 512 * MemoryLayout<Float>.size)
        let loudSamples = [Float](repeating: 0.5, count: 512)
        let loudPCM = loudSamples.withUnsafeBytes { Data($0) }
        guard AudioLevelMeter.normalizedLevel(fromFloat32PCM: silence) == 0,
              AudioLevelMeter.normalizedLevel(fromFloat32PCM: loudPCM) > 0.8 else {
            throw CoreLogicSmokeError.audioLevel
        }

        let service = ModelDownloadService()
        for model in ManagedModel.allCases {
            let manifest = try await service.fetchManifest(for: model)
            let remoteFiles = Set(manifest.siblings.map(\.rfilename))
            for requiredFile in model.requiredFiles where !remoteFiles.contains(requiredFile) {
                throw CoreLogicSmokeError.missingRemoteFile(
                    "\(model.repositoryID)/\(requiredFile)"
                )
            }
            let totalBytes = manifest.siblings.reduce(Int64(0)) { $0 + $1.byteCount }
            print("\(model.repositoryID): \(manifest.siblings.count) files, \(totalBytes) bytes")

            if ProcessInfo.processInfo.environment["FREECOMMUNICATION_SMOKE_DOWNLOAD"] == "1" {
                try await service.download(model: model) { progress in
                    MainActor.preconditionIsolated()
                    if progress.completedBytes == progress.totalBytes {
                        print("\(model.repositoryID): download resume check complete")
                    }
                }
            }
        }
        print("core-logic-smoke-ok")
    }
}
