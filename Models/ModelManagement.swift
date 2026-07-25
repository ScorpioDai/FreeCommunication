import Foundation

enum SettingsTab: String, Hashable {
    case general
    case models
    case recording
    case subtitles
}

enum ManagedModel: String, CaseIterable, Identifiable, Hashable, Sendable {
    case asr
    case nmt

    var id: String { rawValue }

    var roleTitle: String {
        switch self {
        case .asr: L10n.string("语音识别模型")
        case .nmt: L10n.string("英译中模型")
        }
    }

    var displayName: String {
        switch self {
        case .asr: "Nemotron Speech Streaming EN 0.6B · MLX 8-bit"
        case .nmt: "Helsinki-NLP OPUS-MT EN→ZH"
        }
    }

    var repositoryID: String {
        switch self {
        case .asr: "animaslabs/nemotron-speech-streaming-en-0.6b-mlx-8bit"
        case .nmt: "Helsinki-NLP/opus-mt-en-zh"
        }
    }

    var directoryURL: URL {
        switch self {
        case .asr: Defaults.asrModelDirectory
        case .nmt: Defaults.nmtModelDirectory
        }
    }

    var requiredFiles: [String] {
        switch self {
        case .asr:
            ["config.json", "model.safetensors", "tokenizer.model", "tokenizer.vocab", "vocab.txt"]
        case .nmt:
            ["config.json", "pytorch_model.bin", "source.spm", "target.spm", "vocab.json"]
        }
    }

    var isInstalled: Bool {
        requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent($0).path)
        }
    }
}

struct ModelDownloadProgress: Equatable, Sendable {
    var completedBytes: Int64
    var totalBytes: Int64
    var currentFile: String

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

enum ModelInstallState: Equatable {
    case checking
    case missing
    case ready
    case downloading(ModelDownloadProgress)
    case failed(String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

struct LiveTranslationPolicy {
    private struct DisabledInterval {
        var start: TimeInterval
        var end: TimeInterval
    }

    private var disabledIntervals: [DisabledInterval] = []
    private var openDisabledAt: TimeInterval?

    mutating func reset() {
        disabledIntervals.removeAll()
        openDisabledAt = nil
    }

    mutating func setEnabled(_ enabled: Bool, at boundary: TimeInterval) {
        if enabled {
            if let start = openDisabledAt {
                disabledIntervals.append(DisabledInterval(start: start, end: boundary))
                openDisabledAt = nil
            }
        } else if openDisabledAt == nil {
            openDisabledAt = boundary
        }
    }

    func allowsTranslation(for segmentStart: TimeInterval) -> Bool {
        if let openDisabledAt, segmentStart >= openDisabledAt {
            return false
        }
        return !disabledIntervals.contains {
            segmentStart >= $0.start && segmentStart < $0.end
        }
    }
}
