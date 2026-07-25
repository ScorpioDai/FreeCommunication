import Foundation

enum ModelDownloadError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case repositoryUnavailable(Int)
    case unsafePath(String)
    case curlFailed(String)
    case sizeMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            L10n.string("无法创建 Hugging Face 下载地址。")
        case .invalidResponse:
            L10n.string("Hugging Face 返回了无法解析的仓库清单。")
        case .repositoryUnavailable(let status):
            L10n.format("Hugging Face 仓库访问失败（HTTP %d）。", status)
        case .unsafePath(let path):
            L10n.format("仓库包含不安全的文件路径：%@", path)
        case .curlFailed(let message):
            message.isEmpty
                ? L10n.string("模型文件下载失败。")
                : L10n.format("模型文件下载失败：%@", message)
        case .sizeMismatch(let file):
            L10n.format("下载后的文件大小不正确：%@", file)
        }
    }
}

struct HuggingFaceModelManifest: Decodable, Equatable {
    struct Sibling: Decodable, Equatable {
        struct LFSInfo: Decodable, Equatable {
            var size: Int64?
        }

        var rfilename: String
        var size: Int64?
        var lfs: LFSInfo?

        var byteCount: Int64 {
            size ?? lfs?.size ?? 0
        }
    }

    var id: String
    var sha: String
    var siblings: [Sibling]
}

final class ModelDownloadService {
    private let fileManager: FileManager
    private let session: URLSession

    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    func fetchManifest(for model: ManagedModel) async throws -> HuggingFaceModelManifest {
        guard let encodedRepository = model.repositoryID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/api/models/\(encodedRepository)?blobs=true") else {
            throw ModelDownloadError.invalidEndpoint
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelDownloadError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw ModelDownloadError.repositoryUnavailable(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(HuggingFaceModelManifest.self, from: data)
        } catch {
            throw ModelDownloadError.invalidResponse
        }
    }

    func download(
        model: ManagedModel,
        progress: @escaping @MainActor (ModelDownloadProgress) -> Void
    ) async throws {
        let manifest = try await fetchManifest(for: model)
        let files = manifest.siblings.sorted { $0.rfilename < $1.rfilename }
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.byteCount }
        try fileManager.createDirectory(at: model.directoryURL, withIntermediateDirectories: true)

        var completedBytes = files.reduce(Int64(0)) { result, file in
            let destination = model.directoryURL.appendingPathComponent(file.rfilename)
            return result + (isComplete(destination, expectedBytes: file.byteCount) ? file.byteCount : 0)
        }

        await progress(ModelDownloadProgress(
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            currentFile: ""
        ))

        for file in files {
            try Task.checkCancellation()
            let destination = try safeDestination(for: file.rfilename, in: model.directoryURL)
            if isComplete(destination, expectedBytes: file.byteCount) {
                continue
            }

            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let partial = destination.appendingPathExtension("part")
            if file.byteCount > 0, fileSize(at: partial) > file.byteCount {
                try? fileManager.removeItem(at: partial)
            }

            guard let downloadURL = downloadURL(
                repositoryID: manifest.id,
                revision: manifest.sha,
                filename: file.rfilename
            ) else {
                throw ModelDownloadError.invalidEndpoint
            }

            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = [
                "--location",
                "--fail",
                "--silent",
                "--show-error",
                "--retry", "3",
                "--retry-delay", "2",
                "--continue-at", "-",
                "--output", partial.path,
                downloadURL.absoluteString
            ]
            process.standardError = errorPipe
            try process.run()

            while process.isRunning {
                if Task.isCancelled {
                    process.terminate()
                    throw CancellationError()
                }
                let partialBytes = fileSize(at: partial)
                await progress(ModelDownloadProgress(
                    completedBytes: completedBytes + min(file.byteCount, partialBytes),
                    totalBytes: totalBytes,
                    currentFile: file.rfilename
                ))
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                throw ModelDownloadError.curlFailed(errorText)
            }
            guard isComplete(partial, expectedBytes: file.byteCount) else {
                throw ModelDownloadError.sizeMismatch(file.rfilename)
            }

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: partial, to: destination)
            completedBytes += file.byteCount
            await progress(ModelDownloadProgress(
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                currentFile: file.rfilename
            ))
        }
    }

    private func safeDestination(for relativePath: String, in root: URL) throws -> URL {
        let destination = root.appendingPathComponent(relativePath).standardizedFileURL
        let standardizedRoot = root.standardizedFileURL.path + "/"
        guard destination.path.hasPrefix(standardizedRoot) else {
            throw ModelDownloadError.unsafePath(relativePath)
        }
        return destination
    }

    private func isComplete(_ url: URL, expectedBytes: Int64) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        return expectedBytes == 0 || fileSize(at: url) == expectedBytes
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func downloadURL(
        repositoryID: String,
        revision: String,
        filename: String
    ) -> URL? {
        var segmentCharacters = CharacterSet.alphanumerics
        segmentCharacters.insert(charactersIn: "-._~")
        let pathSegments = repositoryID.split(separator: "/").map(String.init)
            + ["resolve", revision]
            + filename.split(separator: "/").map(String.init)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.percentEncodedPath = "/" + pathSegments
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: segmentCharacters) }
            .joined(separator: "/")
        return components.url
    }
}
