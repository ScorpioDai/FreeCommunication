import Foundation

enum AudioArchiveService {
    static func export(chunks: [CapturedChunk], to folder: URL, sessionStart: Date) async throws -> URL? {
        try await Task.detached(priority: .utility) {
            try exportSync(chunks: chunks, to: folder, sessionStart: sessionStart)
        }.value
    }

    private static func exportSync(chunks: [CapturedChunk], to folder: URL, sessionStart: Date) throws -> URL? {
        let existing = chunks
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .sorted { $0.startedAt < $1.startedAt }
        guard !existing.isEmpty else { return nil }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ffmpeg = try resolveFFmpeg()
        let groups = Dictionary(grouping: existing, by: \.channel)
            .sorted { $0.key.rawValue < $1.key.rawValue }

        var channelOutputs: [(url: URL, delayMilliseconds: Int)] = []
        for (channel, channelChunks) in groups {
            let sortedChunks = channelChunks.sorted { $0.startedAt < $1.startedAt }
            guard let first = sortedChunks.first else { continue }
            let listURL = folder.appendingPathComponent(".\(channel.rawValue)-chunks.txt")
            let list = sortedChunks
                .map { "file '\(escapeConcatPath($0.url.path))'" }
                .joined(separator: "\n") + "\n"
            try list.write(to: listURL, atomically: true, encoding: .utf8)

            let channelURL = folder.appendingPathComponent(".\(channel.rawValue).wav")
            try run(
                ffmpeg,
                [
                    "-y",
                    "-hide_banner",
                    "-loglevel", "error",
                    "-f", "concat",
                    "-safe", "0",
                    "-i", listURL.path,
                    "-ac", "1",
                    "-ar", "16000",
                    "-c:a", "pcm_s16le",
                    channelURL.path
                ]
            )
            let delay = max(0, Int(first.startedAt.timeIntervalSince(sessionStart) * 1000))
            channelOutputs.append((channelURL, delay))
        }

        guard !channelOutputs.isEmpty else { return nil }
        let outputURL = folder.appendingPathComponent("audio.wav")
        if channelOutputs.count == 1 {
            let item = channelOutputs[0]
            if item.delayMilliseconds > 0 {
                try run(
                    ffmpeg,
                    [
                        "-y",
                        "-hide_banner",
                        "-loglevel", "error",
                        "-i", item.url.path,
                        "-af", "adelay=\(item.delayMilliseconds)|\(item.delayMilliseconds)",
                        "-ac", "1",
                        "-ar", "16000",
                        "-c:a", "pcm_s16le",
                        outputURL.path
                    ]
                )
            } else {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.copyItem(at: item.url, to: outputURL)
            }
        } else {
            var arguments = ["-y", "-hide_banner", "-loglevel", "error"]
            for item in channelOutputs {
                arguments += ["-i", item.url.path]
            }
            var filters: [String] = []
            var labels: [String] = []
            for (index, item) in channelOutputs.enumerated() {
                let label = "a\(index)"
                filters.append("[\(index):a]adelay=\(item.delayMilliseconds)|\(item.delayMilliseconds)[\(label)]")
                labels.append("[\(label)]")
            }
            filters.append("\(labels.joined())amix=inputs=\(labels.count):duration=longest:normalize=0[out]")
            arguments += [
                "-filter_complex", filters.joined(separator: ";"),
                "-map", "[out]",
                "-ac", "1",
                "-ar", "16000",
                "-c:a", "pcm_s16le",
                outputURL.path
            ]
            try run(ffmpeg, arguments)
        }

        for item in channelOutputs {
            try? FileManager.default.removeItem(at: item.url)
        }
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.lastPathComponent.hasPrefix(".") {
            try? FileManager.default.removeItem(at: url)
        }
        return outputURL
    }

    private static func resolveFFmpeg() throws -> String {
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("Tools", isDirectory: true)
            .appendingPathComponent("ffmpeg")
            .path
        let candidates = [
            bundled,
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ].compactMap { $0 }
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        throw NSError(
            domain: "FreeCommunication",
            code: 70,
            userInfo: [NSLocalizedDescriptionKey: L10n.string("找不到 ffmpeg，无法归档音频。")]
        )
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? L10n.string("ffmpeg 执行失败。")
            throw NSError(domain: "FreeCommunication", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func escapeConcatPath(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }
}
