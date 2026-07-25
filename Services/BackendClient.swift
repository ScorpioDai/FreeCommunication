import Foundation

struct BackendSegmentDTO: Codable {
    var channel: String?
    var speaker: String?
    var start: Double
    var end: Double?
    var source_text: String
    var translated_text: String
}

struct BackendResponse: Codable {
    var id: String?
    var ok: Bool
    var error: String?
    var message: String?
    var text: String?
    var translation: String?
    var record_path: String?
    var srt_path: String?
    var segments: [BackendSegmentDTO]?
    var warnings: [String]?
}

enum BackendClientError: LocalizedError {
    case scriptMissing
    case processUnavailable
    case backend(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .scriptMissing: "找不到后端脚本。"
        case .processUnavailable: "后端进程不可用。"
        case .backend(let message): message
        case .badResponse: "后端返回了无法解析的数据。"
        }
    }
}

final class BackendClient {
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var continuations: [String: CheckedContinuation<BackendResponse, Error>] = [:]
    private let lock = NSLock()

    deinit {
        stop()
    }

    func check(asrPath: String, nmtPath: String, pythonPath: String) async throws -> BackendResponse {
        try await request(
            command: "check",
            payload: [
                "asr_model": asrPath,
                "nmt_model": nmtPath
            ],
            pythonPath: pythonPath
        )
    }

    func transcribeFile(
        inputURL: URL,
        asrPath: String,
        nmtPath: String,
        outputDirectory: URL,
        shouldTranslate: Bool,
        saveOutputs: Bool,
        baseName: String? = nil,
        channel: SegmentChannel = .file,
        offset: TimeInterval = 0,
        pythonPath: String
    ) async throws -> BackendResponse {
        try await request(
            command: "transcribe_file",
            payload: [
                "input": inputURL.path,
                "asr_model": asrPath,
                "nmt_model": nmtPath,
                "output_dir": outputDirectory.path,
                "translate": shouldTranslate ? "true" : "false",
                "save_outputs": saveOutputs ? "true" : "false",
                "base_name": baseName ?? "",
                "channel": channel.rawValue,
                "offset": String(offset)
            ],
            pythonPath: pythonPath
        )
    }

    func transcribeChunks(
        inputURLs: [URL],
        asrPath: String,
        nmtPath: String,
        shouldTranslate: Bool,
        channel: SegmentChannel,
        offset: TimeInterval,
        pythonPath: String
    ) async throws -> BackendResponse {
        let paths = inputURLs.map(\.path)
        let encodedPaths = try JSONSerialization.data(withJSONObject: paths)
        let inputsJSON = String(data: encodedPaths, encoding: .utf8) ?? "[]"
        return try await request(
            command: "transcribe_chunks",
            payload: [
                "inputs_json": inputsJSON,
                "asr_model": asrPath,
                "nmt_model": nmtPath,
                "translate": shouldTranslate ? "true" : "false",
                "channel": channel.rawValue,
                "offset": String(offset)
            ],
            pythonPath: pythonPath
        )
    }

    func streamStart(
        sessionID: String,
        asrPath: String,
        nmtPath: String,
        shouldTranslate: Bool,
        pythonPath: String
    ) async throws -> BackendResponse {
        try await request(
            command: "stream_start",
            payload: [
                "session_id": sessionID,
                "asr_model": asrPath,
                "nmt_model": nmtPath,
                "translate": shouldTranslate ? "true" : "false"
            ],
            pythonPath: pythonPath
        )
    }

    func streamPush(
        sessionID: String,
        pcmData: Data,
        asrPath: String,
        nmtPath: String,
        shouldTranslate: Bool,
        channel: SegmentChannel,
        offset: TimeInterval,
        final: Bool,
        pythonPath: String
    ) async throws -> BackendResponse {
        try await request(
            command: "stream_push",
            payload: [
                "session_id": sessionID,
                "asr_model": asrPath,
                "nmt_model": nmtPath,
                "translate": shouldTranslate ? "true" : "false",
                "channel": channel.rawValue,
                "offset": String(offset),
                "final": final ? "true" : "false",
                "pcm": pcmData.base64EncodedString()
            ],
            pythonPath: pythonPath
        )
    }

    func streamEnd(sessionID: String, pythonPath: String) async throws -> BackendResponse {
        try await request(
            command: "stream_end",
            payload: [
                "session_id": sessionID
            ],
            pythonPath: pythonPath
        )
    }

    func translate(_ text: String, nmtPath: String, pythonPath: String) async throws -> BackendResponse {
        try await request(
            command: "translate",
            payload: [
                "text": text,
                "nmt_model": nmtPath
            ],
            pythonPath: pythonPath
        )
    }

    func stop() {
        lock.lock()
        let pending = continuations.values
        continuations.removeAll()
        let processToStop = process
        process = nil
        input = nil
        lock.unlock()

        pending.forEach { $0.resume(throwing: BackendClientError.processUnavailable) }
        processToStop?.terminate()
    }

    private func request(command: String, payload: [String: String], pythonPath: String) async throws -> BackendResponse {
        try ensureStarted(pythonPath: pythonPath)
        let id = UUID().uuidString
        let request: [String: Any] = [
            "id": id,
            "command": command,
            "payload": payload
        ]
        let data = try JSONSerialization.data(withJSONObject: request)

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations[id] = continuation
            let handle = input
            lock.unlock()

            guard let handle else {
                continuation.resume(throwing: BackendClientError.processUnavailable)
                return
            }

            var line = data
            line.append(0x0A)
            do {
                try handle.write(contentsOf: line)
            } catch {
                complete(id: id, result: .failure(error))
            }
        }
    }

    private func ensureStarted(pythonPath: String) throws {
        lock.lock()
        if let process, process.isRunning {
            lock.unlock()
            return
        }
        lock.unlock()

        let scriptURL = try resolveScriptURL()
        let resolvedPython = resolvePythonPath(configuredPath: pythonPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPython)
        process.arguments = [scriptURL.path, "serve"]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        if let bundledRuntime = bundledRuntimeURL(),
           resolvedPython.hasPrefix(bundledRuntime.path + "/") {
            environment["PYTHONHOME"] = bundledRuntime.path
        }
        if let bundledFFmpeg = bundledFFmpegURL() {
            environment["FREECOMMUNICATION_FFMPEG"] = bundledFFmpeg.path
        }
        let homebrewPaths = "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin"
        let bundledToolsPath = Bundle.main.resourceURL?
            .appendingPathComponent("Tools", isDirectory: true)
            .path
        let preferredPaths = [bundledToolsPath, homebrewPaths]
            .compactMap { $0 }
            .joined(separator: ":")
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            environment["PATH"] = "\(preferredPaths):\(existingPath)"
        } else {
            environment["PATH"] = preferredPaths
        }
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            NSLog("FreeCommunication backend: %@", text)
        }

        try process.run()

        lock.lock()
        self.process = process
        self.input = stdinPipe.fileHandleForWriting
        lock.unlock()
    }

    private func consume(_ data: Data) {
        var lines: [Data] = []

        lock.lock()
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            lines.append(Data(line))
            outputBuffer.removeSubrange(...newline)
        }
        lock.unlock()

        for line in lines where !line.isEmpty {
            handleLine(line)
        }
    }

    private func handleLine(_ line: Data) {
        do {
            let response = try JSONDecoder().decode(BackendResponse.self, from: line)
            guard let id = response.id else { return }
            if response.ok {
                complete(id: id, result: .success(response))
            } else {
                complete(id: id, result: .failure(BackendClientError.backend(response.error ?? "后端执行失败。")))
            }
        } catch {
            NSLog("FreeCommunication bad backend response: %@", String(data: line, encoding: .utf8) ?? "<binary>")
        }
    }

    private func complete(id: String, result: Result<BackendResponse, Error>) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: id)
        lock.unlock()

        switch result {
        case .success(let response):
            continuation?.resume(returning: response)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func resolveScriptURL() throws -> URL {
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("Backend", isDirectory: true)
            .appendingPathComponent("freecommunication_backend.py")
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        let project = projectRootURL()
            .appendingPathComponent("Backend", isDirectory: true)
            .appendingPathComponent("freecommunication_backend.py")
        if FileManager.default.fileExists(atPath: project.path) {
            return project
        }

        throw BackendClientError.scriptMissing
    }

    private func resolvePythonPath(configuredPath: String) -> String {
        let bundledVenv = bundledRuntimeURL()?
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
        if configuredPath == Defaults.systemPythonPath,
           let bundledVenv,
           FileManager.default.isExecutableFile(atPath: bundledVenv.path) {
            return bundledVenv.path
        }
        if FileManager.default.isExecutableFile(atPath: configuredPath) {
            return configuredPath
        }

        if let bundledVenv,
           FileManager.default.isExecutableFile(atPath: bundledVenv.path) {
            return bundledVenv.path
        }

        let projectVenv = projectRootURL()
            .appendingPathComponent("Backend", isDirectory: true)
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
        if configuredPath == Defaults.defaultPythonPath,
           FileManager.default.isExecutableFile(atPath: projectVenv.path) {
            return projectVenv.path
        }

        return configuredPath.isEmpty ? Defaults.defaultPythonPath : configuredPath
    }

    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func bundledRuntimeURL() -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("Backend", isDirectory: true)
            .appendingPathComponent(".venv", isDirectory: true)
    }

    private func bundledFFmpegURL() -> URL? {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("Tools", isDirectory: true)
            .appendingPathComponent("ffmpeg"),
              FileManager.default.isExecutableFile(atPath: url.path) else {
            return nil
        }
        return url
    }
}
