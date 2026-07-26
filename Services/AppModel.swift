import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: SidebarSection = .live
    @Published var settingsTab: SettingsTab = .models
    @Published var mode: CommunicationMode = .call
    @Published var currentSession = TranscriptSession(mode: .call, startedAt: Date(), title: "实时转录")
    @Published var isRunning = false
    @Published var isPreparingSession = false
    @Published var isEndingSession = false
    @Published var isProcessingFile = false
    @Published var microphoneEnabled = true
    @Published var backendHealth: BackendHealth = .unknown
    @Published var statusMessage: String
    @Published var lastSavedURL: URL?
    @Published var subtitleWindowVisible = false
    @Published var translationEnabled = true
    @Published var showMissingModelsAlert = false
    @Published private(set) var modelStates: [ManagedModel: ModelInstallState]
    @Published private(set) var runtimeModelStates: [ManagedModel: ModelRuntimeState]
    @Published private(set) var waveformLevels = Array(repeating: 0.0, count: 90)
    @Published private(set) var interfaceLanguage: InterfaceLanguage

    private let backend = BackendClient()
    private let audioCapture = LiveAudioCapture()
    private let modelDownloadService = ModelDownloadService()
    private var library: RecordingLibrary?
    private var processedChunks = Set<URL>()
    private var subtitleController: SubtitleWindowController?
    private weak var mainWindowBeforeSubtitle: NSWindow?
    private var modelDownloadTasks: [ManagedModel: Task<Void, Never>] = [:]
    private var didCheckModelsOnLaunch = false
    private var liveStreamingActive = false
    private var streamingSessionID: String?
    private var expectedStreamChannels = Set<String>()
    private var streamPendingPCM: [String: Data] = [:]
    private var streamPendingStartedAt: [String: Date] = [:]
    private var streamPushInFlight = Set<String>()
    private let streamFlushThreshold = 48_000
    private var translationPolicy = LiveTranslationPolicy()
    private var latestAudioLevels: [SegmentChannel: (level: Double, updatedAt: Date)] = [:]
    private var waveformUpdateTask: Task<Void, Never>?

    init() {
        let language = L10n.currentLanguage
        interfaceLanguage = language
        statusMessage = L10n.string("准备就绪", language: language)
        modelStates = Dictionary(
            uniqueKeysWithValues: ManagedModel.allCases.map {
                ($0, $0.isInstalled ? .ready : .missing)
            }
        )
        runtimeModelStates = Dictionary(
            uniqueKeysWithValues: ManagedModel.allCases.map {
                ($0, .unavailable)
            }
        )
        currentSession.title = L10n.string("实时转录", language: language)
    }

    var liveSessionActive: Bool {
        isRunning || isEndingSession
    }

    var modelDownloadsActive: Bool {
        modelStates.values.contains { $0.isDownloading }
    }

    func attach(library: RecordingLibrary) {
        self.library = library
    }

    func setInterfaceLanguage(_ language: InterfaceLanguage) {
        guard interfaceLanguage != language else { return }
        UserDefaults.standard.set(language.rawValue, forKey: Defaults.interfaceLanguageKey)
        interfaceLanguage = language
        statusMessage = L10n.string("界面语言已切换", language: language)
    }

    var asrPath: String {
        Defaults.defaultASRPath
    }

    var nmtPath: String {
        Defaults.defaultNMTPath
    }

    var pythonPath: String {
        Defaults.defaultPythonPath
    }

    var liveChunkSeconds: TimeInterval {
        max(2, UserDefaults.standard.double(forKey: Defaults.liveChunkSecondsKey))
    }

    func setMode(_ newMode: CommunicationMode) {
        guard !isRunning && !isPreparingSession else { return }
        mode = newMode
        microphoneEnabled = newMode.capturesMicrophoneByDefault
        translationEnabled = true
        currentSession = TranscriptSession(mode: newMode, startedAt: Date(), title: newMode.title)
    }

    func checkModelsOnLaunch() {
        guard !didCheckModelsOnLaunch else { return }
        didCheckModelsOnLaunch = true
        refreshModelStates()
        Task { [weak self] in
            await self?.preloadInstalledModels()
        }
        if !allModelsInstalled {
            requestMissingModelsPrompt()
        }
    }

    func refreshModelStates() {
        for model in ManagedModel.allCases {
            guard modelStates[model]?.isDownloading != true else { continue }
            if model.isInstalled {
                modelStates[model] = .ready
            } else {
                modelStates[model] = .missing
                runtimeModelStates[model] = .unavailable
            }
        }
    }

    func modelState(for model: ManagedModel) -> ModelInstallState {
        modelStates[model] ?? .checking
    }

    func runtimeModelState(for model: ManagedModel) -> ModelRuntimeState {
        runtimeModelStates[model] ?? .unavailable
    }

    func requestMissingModelsPrompt() {
        refreshModelStates()
        guard !allModelsInstalled else { return }
        showMissingModelsAlert = true
        statusMessage = L10n.string("需要先安装语音识别与翻译模型")
    }

    func beginMissingModelDownloads() {
        showMissingModelsAlert = false
        selection = .settings
        settingsTab = .models
        for model in ManagedModel.allCases where !model.isInstalled {
            download(model)
        }
    }

    func download(_ model: ManagedModel) {
        guard modelDownloadTasks[model] == nil else { return }
        if model.isInstalled {
            modelStates[model] = .ready
            Task { [weak self] in
                _ = await self?.preloadModel(model)
            }
            return
        }

        modelStates[model] = .downloading(ModelDownloadProgress(
            completedBytes: 0,
            totalBytes: 0,
            currentFile: ""
        ))
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await modelDownloadService.download(model: model) { [weak self] progress in
                    self?.modelStates[model] = .downloading(progress)
                }
                guard model.isInstalled else {
                    throw ModelDownloadError.sizeMismatch(model.requiredFiles.joined(separator: ", "))
                }
                modelStates[model] = .ready
                runtimeModelStates[model] = .unavailable
                statusMessage = L10n.format("%@已安装", model.roleTitle)
                backendHealth = .unknown
                modelDownloadTasks[model] = nil
                _ = await preloadModel(model)
            } catch is CancellationError {
                modelStates[model] = model.isInstalled ? .ready : .missing
            } catch {
                modelStates[model] = .failed(error.localizedDescription)
                statusMessage = L10n.format("%@下载失败", model.roleTitle)
            }
            modelDownloadTasks[model] = nil
        }
        modelDownloadTasks[model] = task
    }

    func openModelsDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: Defaults.modelsDirectory,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(Defaults.modelsDirectory)
            statusMessage = L10n.string("已在访达打开模型目录")
        } catch {
            statusMessage = L10n.format("打开模型目录失败：%@", error.localizedDescription)
        }
    }

    func checkBackend() {
        guard !modelDownloadsActive else {
            selection = .settings
            settingsTab = .models
            statusMessage = L10n.string("模型正在下载，完成后才能检查后端")
            backendHealth = .warning(L10n.string("请等待两个模型下载完成。"))
            return
        }
        guard ensureModelsAvailable() else { return }
        backendHealth = .checking
        Task {
            do {
                try await ensureRuntimeModelsReady()
                let response = try await backend.check(asrPath: asrPath, nmtPath: nmtPath, pythonPath: pythonPath)
                let warnings = response.warnings ?? []
                let message = response.message ?? L10n.string("模型目录和基础工具检查通过。")
                backendHealth = warnings.isEmpty ? .ready(message) : .warning(([message] + warnings).joined(separator: "\n"))
            } catch {
                backendHealth = .failed(error.localizedDescription)
            }
        }
    }

    func startSession() {
        guard !isRunning && !isPreparingSession else { return }
        guard ensureModelsAvailable() else { return }
        processedChunks.removeAll()
        resetStreamingState()
        resetWaveform()
        startWaveformUpdates()
        translationEnabled = true
        translationPolicy.reset()
        currentSession = TranscriptSession(mode: mode, startedAt: Date(), title: "\(mode.title) \(TimeFormatter.recordingName())")
        isPreparingSession = true
        isEndingSession = false
        statusMessage = L10n.string("正在等待模型就绪...")

        let directory = Defaults.applicationSupportDirectory
            .appendingPathComponent("LiveChunks", isDirectory: true)
            .appendingPathComponent(currentSession.id.uuidString, isDirectory: true)

        Task {
            do {
                try await ensureRuntimeModelsReady()
                let sessionID = currentSession.id.uuidString
                streamingSessionID = sessionID
                expectedStreamChannels = expectedChannels(for: mode, microphoneEnabled: microphoneEnabled)
                _ = try await backend.streamStart(
                    sessionID: sessionID,
                    asrPath: asrPath,
                    nmtPath: nmtPath,
                    // Always warm NMT once. Per-push flags control whether new
                    // transcript content is translated.
                    shouldTranslate: true,
                    pythonPath: pythonPath
                )
                liveStreamingActive = true
                let recordingStart = Date()
                currentSession.startedAt = recordingStart
                currentSession.title = "\(mode.title) \(TimeFormatter.recordingName(for: recordingStart))"
                statusMessage = mode.capturesSystemAudio
                    ? L10n.string("实时流式转录中：系统声音")
                    : L10n.string("实时流式转录中：麦克风")
                if mode.capturesSystemAudio && microphoneEnabled && mode.capturesMicrophoneByDefault {
                    statusMessage += L10n.string(" + 麦克风")
                }
                try await audioCapture.start(
                    mode: mode,
                    microphoneEnabled: microphoneEnabled,
                    chunkSeconds: liveChunkSeconds,
                    directory: directory,
                    callVoiceProcessingEnabled: UserDefaults.standard.bool(forKey: Defaults.callVoiceProcessingKey),
                    onChunk: { [weak self] chunk in
                        Task { @MainActor in
                            guard self?.liveStreamingActive != true else { return }
                            await self?.processLiveChunk(chunk)
                        }
                    },
                    onPCM: { [weak self] packet in
                        Task { @MainActor in
                            await self?.processLivePCM(packet)
                        }
                    },
                    onLevel: { [weak self] channel, level in
                        Task { @MainActor in
                            self?.updateWaveform(channel: channel, level: level)
                        }
                    }
                )
                isPreparingSession = false
                isRunning = true
                NSLog("FreeCommunication live engine: streaming started session=%@ mode=%@", sessionID, mode.rawValue)
            } catch {
                liveStreamingActive = false
                if let streamingSessionID {
                    _ = try? await backend.streamEnd(sessionID: streamingSessionID, pythonPath: pythonPath)
                }
                _ = await audioCapture.stop()
                resetStreamingState()
                stopWaveformUpdates()
                isPreparingSession = false
                isRunning = false
                isEndingSession = false
                statusMessage = L10n.format("流式启动失败：%@", error.localizedDescription)
                backendHealth = .warning(error.localizedDescription)
                NSLog("FreeCommunication live engine: streaming failed %@", error.localizedDescription)
            }
        }
    }

    func stopSession() {
        guard isRunning else { return }
        closeSubtitleWindow()
        isRunning = false
        isEndingSession = true
        stopWaveformUpdates()
        statusMessage = L10n.string("正在停止音频捕捉...")
        NSLog("FreeCommunication live engine: stop requested")
        Task {
            let finalChunks = await audioCapture.stop()
            NSLog("FreeCommunication live engine: audio capture stopped chunks=%ld", finalChunks.count)
            if liveStreamingActive {
                statusMessage = L10n.string("正在完成最后一段转录...")
                try? await Task.sleep(nanoseconds: 200_000_000)
                await flushAllStreamingChannels(final: true)
                if let streamingSessionID {
                    _ = try? await backend.streamEnd(sessionID: streamingSessionID, pythonPath: pythonPath)
                }
            } else {
                for chunk in finalChunks {
                    await processLiveChunk(chunk)
                }
            }
            resetStreamingState()
            currentSession.endedAt = Date()
            statusMessage = L10n.string("正在写入记录...")
            do {
                if let url = try await library?.save(session: currentSession, audioChunks: finalChunks) {
                    lastSavedURL = url
                    statusMessage = L10n.format("已保存到 %@", recordDisplayName(for: url))
                    await library?.reload()
                    currentSession = TranscriptSession(mode: mode, startedAt: Date(), title: mode.title)
                    translationEnabled = true
                    translationPolicy.reset()
                } else {
                    statusMessage = L10n.string("记录库尚未准备好。")
                }
            } catch {
                statusMessage = L10n.format("保存失败：%@", error.localizedDescription)
            }
            isEndingSession = false
            NSLog("FreeCommunication live engine: stop finished")
        }
    }

    func toggleMicrophone() {
        guard mode.capturesMicrophoneByDefault else { return }
        microphoneEnabled.toggle()
        guard isRunning else { return }
        Task {
            do {
                try await audioCapture.setMicrophoneEnabled(microphoneEnabled)
                statusMessage = L10n.string(microphoneEnabled ? "麦克风已开启" : "麦克风已关闭")
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func setTranslationEnabled(_ enabled: Bool) {
        guard translationEnabled != enabled else { return }
        let boundary = max(0, Date().timeIntervalSince(currentSession.startedAt))
        translationPolicy.setEnabled(enabled, at: boundary)
        translationEnabled = enabled
        statusMessage = L10n.string(enabled ? "翻译已开启，实时转录继续" : "翻译已关闭，实时转录继续")
        NSLog(
            "FreeCommunication live engine: translation %@ at %.3f",
            enabled ? "enabled" : "disabled",
            boundary
        )
    }

    func toggleTranslation() {
        setTranslationEnabled(!translationEnabled)
    }

    func processSelectedMedia(translate: Bool) {
        guard let url = FilePanelService.chooseMediaFile() else { return }
        processMedia(url: url, translate: translate)
    }

    func processMedia(url: URL, translate: Bool) {
        guard ensureModelsAvailable() else { return }
        isProcessingFile = true
        selection = .files
        statusMessage = translate
            ? L10n.format("正在转录并翻译 %@", url.lastPathComponent)
            : L10n.format("正在转录 %@", url.lastPathComponent)
        Task {
            do {
                try await ensureRuntimeModelsReady()
                let response = try await backend.transcribeFile(
                    inputURL: url,
                    asrPath: asrPath,
                    nmtPath: nmtPath,
                    outputDirectory: Defaults.recordingsDirectory,
                    shouldTranslate: translate,
                    saveOutputs: true,
                    baseName: url.deletingPathExtension().lastPathComponent,
                    channel: .file,
                    pythonPath: pythonPath
                )
                isProcessingFile = false
                if let path = response.record_path {
                    let url = URL(fileURLWithPath: path)
                    lastSavedURL = url
                    statusMessage = L10n.format("已保存 %@", recordDisplayName(for: url))
                } else {
                    statusMessage = L10n.string("处理完成")
                }
                await library?.reload()
            } catch {
                isProcessingFile = false
                statusMessage = L10n.format("处理失败：%@", error.localizedDescription)
            }
        }
    }

    func copyCurrent(_ scope: CopyScope) {
        let text: String
        switch scope {
        case .source:
            text = currentSession.sourceText
        case .translation:
            text = currentSession.translatedText
        case .bilingual:
            text = currentSession.bilingualText
        }
        ClipboardService.copy(text)
        statusMessage = scope.title
    }

    func copy(document: RecordingDocument, scope: CopyScope) {
        let text: String
        switch scope {
        case .source:
            text = document.sourceText
        case .translation:
            text = document.translatedText
        case .bilingual:
            text = document.bilingualText
        }
        ClipboardService.copy(text)
        statusMessage = scope.title
    }

    func rename(document: RecordingDocument, to title: String) {
        do {
            try library?.rename(document, to: title)
            Task { await library?.reload() }
        } catch {
            statusMessage = L10n.format("重命名失败：%@", error.localizedDescription)
        }
    }

    func delete(document: RecordingDocument) {
        do {
            try library?.delete(document)
            Task { await library?.reload() }
        } catch {
            statusMessage = L10n.format("删除失败：%@", error.localizedDescription)
        }
    }

    func openRecordingsDirectory() {
        do {
            try FileManager.default.createDirectory(at: Defaults.recordingsDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Defaults.recordingsDirectory)
            statusMessage = L10n.string("已在访达打开记录目录")
        } catch {
            statusMessage = L10n.format("打开记录目录失败：%@", error.localizedDescription)
        }
    }

    func reveal(document: RecordingDocument) {
        NSWorkspace.shared.activateFileViewerSelecting([document.url])
        statusMessage = L10n.string("已在访达中显示记录")
    }

    func toggleSubtitleWindow() {
        if subtitleWindowVisible {
            closeSubtitleWindow()
        } else {
            let mainWindow = applicationMainWindow()
            let controller = SubtitleWindowController(appModel: self)
            controller.show()
            subtitleController = controller
            subtitleWindowVisible = true
            mainWindowBeforeSubtitle = mainWindow
            mainWindow?.orderOut(nil)
        }
    }

    func showMainWindow() {
        let window = mainWindowBeforeSubtitle ?? applicationMainWindow()
        window?.makeKeyAndOrderFront(nil)
        mainWindowBeforeSubtitle = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeSubtitleWindow(restoreMainWindow: Bool = true) {
        subtitleController?.close()
        subtitleController = nil
        subtitleWindowVisible = false
        if restoreMainWindow {
            showMainWindow()
        }
    }

    private func processLiveChunk(_ chunk: CapturedChunk) async {
        guard !processedChunks.contains(chunk.url) else { return }
        processedChunks.insert(chunk.url)
        let offset = chunk.startedAt.timeIntervalSince(currentSession.startedAt)
        let shouldTranslate = translationEnabled
        do {
            let response = try await backend.transcribeFile(
                inputURL: chunk.url,
                asrPath: asrPath,
                nmtPath: nmtPath,
                outputDirectory: Defaults.recordingsDirectory,
                shouldTranslate: shouldTranslate,
                saveOutputs: false,
                channel: chunk.channel,
                offset: offset,
                pythonPath: pythonPath
            )
            let segments = (response.segments ?? []).map { dto -> TranscriptSegment in
                let channel = SegmentChannel(rawValue: dto.channel ?? chunk.channel.rawValue) ?? chunk.channel
                return TranscriptSegment(
                    channel: channel,
                    speaker: speakerName(for: channel, backendSpeaker: dto.speaker),
                    start: dto.start,
                    end: dto.end,
                    sourceText: dto.source_text,
                    translatedText: translationAllowed(for: dto.start)
                        ? dto.translated_text
                        : "",
                    isFinal: true
                )
            }
            let nonEmpty = segments.filter { !$0.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !nonEmpty.isEmpty {
                appendLiveSegments(nonEmpty)
                applyCallEchoSuppression()
                statusMessage = L10n.format("已更新 %d 条转录", nonEmpty.count)
            }
        } catch {
            statusMessage = L10n.format("分片处理失败：%@", error.localizedDescription)
        }
    }

    private func recordDisplayName(for url: URL) -> String {
        url.lastPathComponent == "transcript.txt" ? url.deletingLastPathComponent().lastPathComponent : url.lastPathComponent
    }

    private func processLivePCM(_ packet: CapturedPCMChunk) async {
        guard liveStreamingActive else { return }
        let key = packet.channel.rawValue
        expectedStreamChannels.insert(key)
        if streamPendingPCM[key] == nil {
            streamPendingPCM[key] = Data()
            streamPendingStartedAt[key] = packet.startedAt
        }
        streamPendingPCM[key]?.append(packet.data)
        if (streamPendingPCM[key]?.count ?? 0) >= streamFlushThreshold {
            await flushStreamingChannel(packet.channel, final: false)
        }
    }

    private func updateWaveform(channel: SegmentChannel, level: Double) {
        guard isRunning || isPreparingSession else { return }
        latestAudioLevels[channel] = (min(1, max(0, level)), Date())
    }

    private func sampleWaveform() {
        let now = Date()
        let recentLevels = latestAudioLevels.values
            .filter { now.timeIntervalSince($0.updatedAt) < 0.4 }
            .map(\.level)
        let measured = recentLevels.max() ?? 0
        let previous = waveformLevels.last ?? 0
        let visualLevel = measured >= previous ? measured : max(measured, previous * 0.72)
        waveformLevels.removeFirst()
        waveformLevels.append(visualLevel)
    }

    private func startWaveformUpdates() {
        waveformUpdateTask?.cancel()
        waveformUpdateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 65_000_000)
                guard let self else { return }
                sampleWaveform()
            }
        }
    }

    private func stopWaveformUpdates() {
        waveformUpdateTask?.cancel()
        waveformUpdateTask = nil
        latestAudioLevels.removeAll()
        waveformLevels = Array(repeating: 0, count: 90)
    }

    private func resetWaveform() {
        waveformUpdateTask?.cancel()
        waveformUpdateTask = nil
        waveformLevels = Array(repeating: 0, count: 90)
        latestAudioLevels.removeAll()
    }

    private func flushAllStreamingChannels(final: Bool) async {
        let channels = expectedStreamChannels.compactMap(SegmentChannel.init(rawValue:))
        for channel in channels {
            await flushStreamingChannel(channel, final: final)
        }
    }

    private func flushStreamingChannel(_ channel: SegmentChannel, final: Bool) async {
        let key = channel.rawValue
        while streamPushInFlight.contains(key) {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard liveStreamingActive, let streamingSessionID else { return }
        let data = streamPendingPCM[key] ?? Data()
        guard !data.isEmpty || final else { return }
        let startedAt = streamPendingStartedAt[key] ?? Date()
        streamPendingPCM[key] = Data()
        streamPendingStartedAt[key] = nil
        streamPushInFlight.insert(key)
        defer {
            streamPushInFlight.remove(key)
            if (streamPendingPCM[key]?.isEmpty == false) && !final {
                Task { @MainActor in
                    await self.flushStreamingChannel(channel, final: false)
                }
            }
        }

        do {
            let requestStartedAt = Date()
            let shouldTranslate = translationEnabled
            let response = try await backend.streamPush(
                sessionID: streamingSessionID,
                pcmData: data,
                asrPath: asrPath,
                nmtPath: nmtPath,
                shouldTranslate: shouldTranslate,
                channel: channel,
                offset: startedAt.timeIntervalSince(currentSession.startedAt),
                final: final,
                pythonPath: pythonPath
            )
            updateStreamingSegments(response.segments ?? [], channel: channel, final: final)
            let count = response.segments?.count ?? 0
            let translatedCount = (response.segments ?? []).filter {
                !$0.translated_text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            let elapsedMilliseconds = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            NSLog(
                "FreeCommunication live engine: stream push channel=%@ final=%@ translate=%@ bytes=%ld segments=%ld translated=%ld elapsed_ms=%ld",
                channel.rawValue,
                final ? "true" : "false",
                shouldTranslate ? "true" : "false",
                data.count,
                count,
                translatedCount,
                elapsedMilliseconds
            )
            if count > 0 {
                statusMessage = final
                    ? L10n.string("流式转录已完成")
                    : L10n.format("实时流式更新 %d 条转录", count)
            }
        } catch {
            statusMessage = L10n.format("流式处理失败：%@", error.localizedDescription)
        }
    }

    private func updateStreamingSegments(_ dtos: [BackendSegmentDTO], channel: SegmentChannel, final: Bool) {
        let previous = currentSession.segments.filter { $0.channel == channel }
        let updated = dtos
            .filter { !$0.source_text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { dto -> TranscriptSegment in
                let sourceText = dto.source_text.trimmingCharacters(in: .whitespacesAndNewlines)
                let translatedText = resolvedStreamingTranslation(
                    incomingSource: sourceText,
                    incomingTranslation: dto.translated_text,
                    incomingStart: dto.start,
                    previous: previous
                )
                let allowedTranslation = translationAllowed(for: dto.start)
                    ? translatedText
                    : ""
                return TranscriptSegment(
                    channel: SegmentChannel(rawValue: dto.channel ?? channel.rawValue) ?? channel,
                    speaker: speakerName(
                        for: SegmentChannel(rawValue: dto.channel ?? channel.rawValue) ?? channel,
                        backendSpeaker: dto.speaker
                    ),
                    start: dto.start,
                    end: dto.end,
                    sourceText: sourceText,
                    translatedText: allowedTranslation,
                    isFinal: final || !allowedTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        guard shouldAcceptStreamingUpdate(previous: previous, updated: updated, channel: channel, final: final) else {
            return
        }
        currentSession.segments.removeAll { $0.channel == channel }
        currentSession.segments.append(contentsOf: updated)
        applyCallEchoSuppression()
        currentSession.segments.sort { $0.start < $1.start }
    }

    private func shouldAcceptStreamingUpdate(
        previous: [TranscriptSegment],
        updated: [TranscriptSegment],
        channel: SegmentChannel,
        final: Bool
    ) -> Bool {
        guard !updated.isEmpty else {
            if !previous.isEmpty {
                NSLog("FreeCommunication live engine: ignored empty stream update channel=%@", channel.rawValue)
            }
            return previous.isEmpty
        }

        let previousWords = normalizedWords(previous.map(\.sourceText).joined(separator: " ")).count
        let updatedWords = normalizedWords(updated.map(\.sourceText).joined(separator: " ")).count
        if previousWords > 0, updatedWords + 5 < previousWords {
            NSLog(
                "FreeCommunication live engine: ignored shorter stream update channel=%@ final=%@ previous_words=%ld updated_words=%ld",
                channel.rawValue,
                final ? "true" : "false",
                previousWords,
                updatedWords
            )
            return false
        }
        return true
    }

    private func speakerName(for channel: SegmentChannel, backendSpeaker: String?) -> String {
        switch channel {
        case .microphone:
            return "我"
        case .system:
            return mode == .call ? "对方" : "电脑音频"
        case .file:
            return "音频"
        }
    }

    private func applyCallEchoSuppression() {
        guard mode == .call else { return }
        let systemSegments = currentSession.segments.filter { $0.channel == .system }
        guard !systemSegments.isEmpty else { return }

        let before = currentSession.segments.count
        currentSession.segments.removeAll { candidate in
            guard candidate.channel == .microphone else { return false }
            return systemSegments.contains { isLikelyMicrophoneEcho(candidate, of: $0) }
        }
        let suppressed = before - currentSession.segments.count
        if suppressed > 0 {
            NSLog("FreeCommunication call mode: suppressed %ld microphone echo segment(s)", suppressed)
        }
    }

    private func isLikelyMicrophoneEcho(_ microphone: TranscriptSegment, of system: TranscriptSegment) -> Bool {
        let micWords = normalizedWords(microphone.sourceText)
        let systemWords = normalizedWords(system.sourceText)
        guard micWords.count >= 6, systemWords.count >= 6 else { return false }

        let micEnd = microphone.end ?? microphone.start
        let systemEnd = system.end ?? system.start
        let overlap = min(micEnd, systemEnd) - max(microphone.start, system.start)
        let nearInTime = overlap > -1.5
            || abs(microphone.start - system.start) <= 7.0
            || abs(micEnd - systemEnd) <= 7.0
        guard nearInTime else { return false }

        let similarity = tokenContainmentSimilarity(micWords, systemWords)
        let micText = micWords.joined(separator: " ")
        let systemText = systemWords.joined(separator: " ")
        let contained = micWords.count >= 8 && (micText.contains(systemText) || systemText.contains(micText))
        return similarity >= 0.62 || contained
    }

    private func normalizedWords(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    private func tokenContainmentSimilarity(_ lhs: [String], _ rhs: [String]) -> Double {
        let left = Set(lhs)
        let right = Set(rhs)
        let denominator = min(left.count, right.count)
        guard denominator > 0 else { return 0 }
        return Double(left.intersection(right).count) / Double(denominator)
    }

    private func resolvedStreamingTranslation(
        incomingSource: String,
        incomingTranslation: String,
        incomingStart: TimeInterval,
        previous: [TranscriptSegment]
    ) -> String {
        let trimmedTranslation = incomingTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTranslation.isEmpty {
            return trimmedTranslation
        }

        let matching = previous.first { segment in
            let startDelta = abs(segment.start - incomingStart)
            guard startDelta < 0.35, !segment.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            let oldSource = segment.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            return incomingSource == oldSource
                || incomingSource.hasPrefix(oldSource)
                || oldSource.hasPrefix(incomingSource)
        }

        return matching?.translatedText ?? ""
    }

    private var allModelsInstalled: Bool {
        ManagedModel.allCases.allSatisfy(\.isInstalled)
    }

    private func preloadInstalledModels() async {
        for model in ManagedModel.allCases where model.isInstalled {
            _ = await preloadModel(model)
        }
    }

    private func preloadModel(_ model: ManagedModel) async -> Bool {
        guard model.isInstalled else {
            runtimeModelStates[model] = .unavailable
            return false
        }

        switch runtimeModelState(for: model) {
        case .ready:
            return true
        case .loading:
            while runtimeModelState(for: model) == .loading {
                guard !Task.isCancelled else { return false }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            return runtimeModelState(for: model).isReady
        case .unavailable, .failed:
            break
        }

        runtimeModelStates[model] = .loading
        NSLog("FreeCommunication model warmup: started model=%@", model.rawValue)
        do {
            _ = try await backend.warmModel(
                model,
                asrPath: asrPath,
                nmtPath: nmtPath,
                pythonPath: pythonPath
            )
            runtimeModelStates[model] = .ready
            NSLog("FreeCommunication model warmup: ready model=%@", model.rawValue)
            return true
        } catch {
            runtimeModelStates[model] = .failed(error.localizedDescription)
            statusMessage = L10n.format("%@加载失败：%@", model.roleTitle, error.localizedDescription)
            NSLog(
                "FreeCommunication model warmup: failed model=%@ error=%@",
                model.rawValue,
                error.localizedDescription
            )
            return false
        }
    }

    private func ensureRuntimeModelsReady() async throws {
        for model in ManagedModel.allCases {
            guard await preloadModel(model) else {
                let detail: String
                if case .failed(let message) = runtimeModelState(for: model) {
                    detail = message
                } else {
                    detail = L10n.string("模型文件不可用")
                }
                throw BackendClientError.backend(
                    L10n.format("%@尚未就绪：%@", model.roleTitle, detail)
                )
            }
        }
    }

    private func applicationMainWindow() -> NSWindow? {
        if let mainWindowBeforeSubtitle {
            return mainWindowBeforeSubtitle
        }
        if let mainWindow = NSApp.mainWindow, !(mainWindow is NSPanel) {
            return mainWindow
        }
        return NSApp.windows.first {
            !($0 is NSPanel) && $0.title == "FreeCommunication"
        }
    }

    private func ensureModelsAvailable() -> Bool {
        refreshModelStates()
        guard !modelDownloadsActive else {
            selection = .settings
            settingsTab = .models
            statusMessage = L10n.string("模型正在下载，请等待完成")
            return false
        }
        guard allModelsInstalled else {
            requestMissingModelsPrompt()
            return false
        }
        return true
    }

    private func translationAllowed(for segmentStart: TimeInterval) -> Bool {
        translationPolicy.allowsTranslation(for: segmentStart)
    }

    private func expectedChannels(for mode: CommunicationMode, microphoneEnabled: Bool) -> Set<String> {
        var channels = Set<String>()
        if mode.capturesSystemAudio {
            channels.insert(SegmentChannel.system.rawValue)
        }
        if microphoneEnabled && mode.capturesMicrophoneByDefault {
            channels.insert(SegmentChannel.microphone.rawValue)
        }
        return channels
    }

    private func resetStreamingState() {
        liveStreamingActive = false
        streamingSessionID = nil
        expectedStreamChannels.removeAll()
        streamPendingPCM.removeAll()
        streamPendingStartedAt.removeAll()
        streamPushInFlight.removeAll()
    }

    private func appendLiveSegments(_ segments: [TranscriptSegment]) {
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = currentSession.segments.last, shouldMerge(last, with: segment) {
                currentSession.segments[currentSession.segments.count - 1] = merged(last, segment)
            } else {
                currentSession.segments.append(segment)
            }
        }
        currentSession.segments.sort { $0.start < $1.start }
    }

    private func shouldMerge(_ previous: TranscriptSegment, with next: TranscriptSegment) -> Bool {
        guard previous.channel == next.channel, previous.speaker == next.speaker else { return false }
        let previousEnd = previous.end ?? previous.start
        guard next.start >= previous.start, next.start - previousEnd <= max(2.5, liveChunkSeconds) else { return false }
        let combinedWordCount = previous.sourceText.split(separator: " ").count + next.sourceText.split(separator: " ").count
        guard combinedWordCount <= 56 else { return false }

        let gap = next.start - previousEnd
        let previousWordCount = previous.sourceText.split(separator: " ").count
        let nextWordCount = next.sourceText.split(separator: " ").count
        return gap <= 0.25
            || !previous.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).hasTerminalSentencePunctuation
            || previousWordCount <= 5
            || nextWordCount <= 5
    }

    private func merged(_ previous: TranscriptSegment, _ next: TranscriptSegment) -> TranscriptSegment {
        var merged = previous
        merged.end = next.end ?? previous.end
        merged.sourceText = joinText(previous.sourceText, next.sourceText, separator: " ")
        merged.translatedText = joinText(previous.translatedText, next.translatedText, separator: "")
        return merged
    }

    private func joinText(_ lhs: String, _ rhs: String, separator: String) -> String {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + separator + right
    }
}

private extension String {
    var hasTerminalSentencePunctuation: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return ".!?。！？".contains(last)
    }
}
