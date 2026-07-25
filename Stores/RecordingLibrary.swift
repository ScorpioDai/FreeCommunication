import Foundation

@MainActor
final class RecordingLibrary: ObservableObject {
    @Published private(set) var documents: [RecordingDocument] = []
    @Published var selection: RecordingDocument.ID?

    let directory = Defaults.recordingsDirectory

    func reload() async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let loaded = files
                .compactMap(loadDocument)
                .sorted { $0.createdAt > $1.createdAt }
            documents = loaded
            if selection == nil || !loaded.contains(where: { $0.id == selection }) {
                selection = loaded.first?.id
            }
        } catch {
            documents = []
        }
    }

    func selectedDocument() -> RecordingDocument? {
        guard let selection else { return documents.first }
        return documents.first { $0.id == selection }
    }

    func save(session: TranscriptSession, audioChunks: [CapturedChunk] = []) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = TimeFormatter.recordingName(for: session.startedAt)
        let folder = uniqueFolder(baseName: name)
        let url = folder.appendingPathComponent("transcript.txt")
        let body = RecordingTextCodec.encode(
            title: session.title,
            mode: session.mode.title,
            createdAt: session.startedAt,
            segments: session.segments
        )
        try body.write(to: url, atomically: true, encoding: .utf8)
        if !audioChunks.isEmpty {
            do {
                _ = try await AudioArchiveService.export(chunks: audioChunks, to: folder, sessionStart: session.startedAt)
            } catch {
                NSLog("FreeCommunication recording audio archive failed: %@", error.localizedDescription)
            }
        }
        return url
    }

    func rename(_ document: RecordingDocument, to newTitle: String) throws {
        let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if document.isFolderBacked {
            let destination = uniqueFolder(baseName: clean, create: false)
            try FileManager.default.moveItem(at: document.containerURL, to: destination)
        } else {
            let destination = uniqueURL(baseName: clean, extension: "txt")
            try FileManager.default.moveItem(at: document.url, to: destination)
        }
    }

    func delete(_ document: RecordingDocument) throws {
        if document.isFolderBacked {
            try FileManager.default.removeItem(at: document.containerURL)
        } else {
            try FileManager.default.removeItem(at: document.url)
            let srt = document.url.deletingPathExtension().appendingPathExtension("srt")
            if FileManager.default.fileExists(atPath: srt.path) {
                try? FileManager.default.removeItem(at: srt)
            }
        }
    }

    func uniqueURL(baseName: String, extension pathExtension: String) -> URL {
        let allowed = CharacterSet(charactersIn: "/:").union(.newlines)
        let safeBase = baseName
            .components(separatedBy: allowed)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeBase.isEmpty ? "Recording" : safeBase
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(pathExtension)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index)").appendingPathExtension(pathExtension)
            index += 1
        }
        return candidate
    }

    func uniqueFolder(baseName: String, create: Bool = true) -> URL {
        let allowed = CharacterSet(charactersIn: "/:").union(.newlines)
        let safeBase = baseName
            .components(separatedBy: allowed)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeBase.isEmpty ? "Recording" : safeBase
        var candidate = directory.appendingPathComponent(base, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index)", isDirectory: true)
            index += 1
        }
        if create {
            try? FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        }
        return candidate
    }

    private func loadDocument(_ itemURL: URL) -> RecordingDocument? {
        let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey])
        let isDirectory = values?.isDirectory == true
        let url: URL
        let containerURL: URL
        if isDirectory {
            let transcript = itemURL.appendingPathComponent("transcript.txt")
            if FileManager.default.fileExists(atPath: transcript.path) {
                url = transcript
            } else {
                guard let fallback = try? FileManager.default
                    .contentsOfDirectory(at: itemURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    .first(where: { $0.pathExtension.lowercased() == "txt" }) else {
                    return nil
                }
                url = fallback
            }
            containerURL = itemURL
        } else {
            guard itemURL.pathExtension.lowercased() == "txt" else { return nil }
            url = itemURL
            containerURL = itemURL
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fileValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let date = values?.creationDate ?? values?.contentModificationDate ?? Date()
        let createdAt = fileValues?.creationDate ?? fileValues?.contentModificationDate ?? date
        let parsed = RecordingTextCodec.decode(content)
        let audio = preferredAudioURL(in: containerURL, folderBacked: isDirectory)
        let srt = preferredSRTURL(for: url, container: containerURL, folderBacked: isDirectory)
        return RecordingDocument(
            id: containerURL,
            url: url,
            containerURL: containerURL,
            audioURL: audio,
            srtURL: srt,
            title: isDirectory ? containerURL.lastPathComponent : url.deletingPathExtension().lastPathComponent,
            createdAt: createdAt,
            sourceText: parsed.source,
            translatedText: parsed.translation,
            bilingualText: parsed.bilingual.isEmpty ? content : parsed.bilingual,
            segments: parsed.segments
        )
    }

    private func preferredAudioURL(in container: URL, folderBacked: Bool) -> URL? {
        guard folderBacked else { return nil }
        for name in ["audio.wav", "audio.m4a", "microphone.wav", "system.wav"] {
            let url = container.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func preferredSRTURL(for transcript: URL, container: URL, folderBacked: Bool) -> URL? {
        let candidates = folderBacked
            ? [container.appendingPathComponent("subtitles.srt"), transcript.deletingPathExtension().appendingPathExtension("srt")]
            : [transcript.deletingPathExtension().appendingPathExtension("srt")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum RecordingTextCodec {
    static func encode(title: String, mode: String, createdAt: Date, segments: [TranscriptSegment]) -> String {
        var lines: [String] = [
            "# \(title)",
            "模式: \(mode)",
            "时间: \(ISO8601DateFormatter().string(from: createdAt))",
            ""
        ]

        let hasTranslation = segments.contains { !$0.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if hasTranslation {
            lines.append("## 转录+翻译")
            for segment in segments {
                lines.append("[\(segment.timestamp)] \(segment.speaker)")
                if !segment.sourceText.isEmpty {
                    lines.append(segment.sourceText)
                }
                if !segment.translatedText.isEmpty {
                    lines.append(segment.translatedText)
                }
                lines.append("")
            }
        } else {
            lines.append("## 转录")
            lines.append(contentsOf: segments.map { "[\($0.timestamp)] \($0.speaker): \($0.sourceText)" })
        }
        return lines.joined(separator: "\n")
    }

    static func decode(_ content: String) -> (source: String, translation: String, bilingual: String, segments: [TranscriptSegment]) {
        if content.contains("## 原文") {
            let source = section("## 原文", before: "## 译文", in: content)
            let translation = section("## 译文", before: "## 原文+译文", in: content)
            let bilingual = section("## 原文+译文", before: nil, in: content)
            return (source, translation, bilingual, parseSegments(from: bilingual))
        }

        if content.contains("## 转录+翻译") {
            let bilingual = section("## 转录+翻译", before: nil, in: content)
            let parsed = parseBilingualBlocks(bilingual)
            return (parsed.source, parsed.translation, bilingual, parsed.segments)
        }

        if content.contains("## 转录") {
            let source = section("## 转录", before: nil, in: content)
            return (source, "", source, parseSegments(from: source))
        }

        return ("", "", content, [])
    }

    private static func section(_ marker: String, before endMarker: String?, in content: String) -> String {
        guard let start = content.range(of: marker) else { return "" }
        let bodyStart = start.upperBound
        let bodyEnd: String.Index
        if let endMarker, let end = content[bodyStart...].range(of: endMarker) {
            bodyEnd = end.lowerBound
        } else {
            bodyEnd = content.endIndex
        }
        return content[bodyStart..<bodyEnd].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseBilingualBlocks(_ content: String) -> (source: String, translation: String, segments: [TranscriptSegment]) {
        var sourceLines: [String] = []
        var translationLines: [String] = []
        var segments: [TranscriptSegment] = []
        let blocks = content.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }

            let body: ArraySlice<String>
            if lines[0].hasPrefix("[") {
                body = lines.dropFirst()
            } else {
                body = lines[...]
            }
            if let source = body.first {
                sourceLines.append(source)
            }
            let translation = body.count >= 2 ? body[body.index(body.startIndex, offsetBy: 1)] : ""
            if body.count >= 2 {
                translationLines.append(translation)
            }
            if lines[0].hasPrefix("["),
               let parsed = parseHeader(lines[0]),
               let source = body.first {
                segments.append(
                    TranscriptSegment(
                        channel: parsed.speaker == "电脑音频" || parsed.speaker == "对方" ? .system : .microphone,
                        speaker: parsed.speaker,
                        start: parsed.start,
                        end: nil,
                        sourceText: source,
                        translatedText: translation,
                        isFinal: true
                    )
                )
            }
        }
        return (sourceLines.joined(separator: "\n"), translationLines.joined(separator: "\n"), segments)
    }

    private static func parseSegments(from content: String) -> [TranscriptSegment] {
        content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> TranscriptSegment? in
                let value = String(line)
                if let parsed = parseHeaderLineWithText(value) {
                    return TranscriptSegment(
                        channel: parsed.speaker == "电脑音频" || parsed.speaker == "对方" ? .system : .microphone,
                        speaker: parsed.speaker,
                        start: parsed.start,
                        end: nil,
                        sourceText: parsed.text,
                        translatedText: "",
                        isFinal: true
                    )
                }
                return nil
            }
    }

    private static func parseHeader(_ line: String) -> (start: TimeInterval, speaker: String)? {
        guard let close = line.firstIndex(of: "]") else { return nil }
        let clock = line[line.index(after: line.startIndex)..<close]
        let speaker = line[line.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (clockToSeconds(String(clock)), speaker)
    }

    private static func parseHeaderLineWithText(_ line: String) -> (start: TimeInterval, speaker: String, text: String)? {
        guard let close = line.firstIndex(of: "]") else { return nil }
        let clock = String(line[line.index(after: line.startIndex)..<close])
        let rest = line[line.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let speaker = rest[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        let text = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (clockToSeconds(clock), speaker, text)
    }

    private static func clockToSeconds(_ value: String) -> TimeInterval {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return 0
    }
}
