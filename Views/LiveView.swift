import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(Defaults.subtitleFontSizeKey) private var subtitleFontSize = 24.0

    var body: some View {
        if appModel.liveSessionActive {
            activeSessionView
        } else {
            setupView
        }
    }

    private var setupView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    modeGrid
                }
                .padding(28)
            }

            bottomBar
        }
    }

    private var activeSessionView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                activeHeader
                activeSurface
            }
            .padding(28)

            activeBottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(setupTitle)
                    .font(.system(size: 34, weight: .semibold))
                Text(appModel.statusMessage)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var setupTitle: String {
        if appModel.isPreparingSession {
            return L10n.string("正在准备流式转录...")
        }
        return L10n.string("选择一种沟通场景")
    }

    private var modeGrid: some View {
        HStack(spacing: 18) {
            ForEach(CommunicationMode.allCases) { mode in
                Button {
                    appModel.setMode(mode)
                } label: {
                    ModeCard(mode: mode, isSelected: appModel.mode == mode)
                        .id(appModel.interfaceLanguage)
                }
                .buttonStyle(.plain)
                .disabled(appModel.isRunning || appModel.isPreparingSession)
            }
        }
        .padding(.top, 22)
    }

    private var liveSurface: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(appModel.mode.title, systemImage: appModel.mode.systemImage)
                    .font(.headline)
                Spacer()
                if appModel.mode.capturesMicrophoneByDefault {
                    Button {
                        appModel.toggleMicrophone()
                    } label: {
                        Label(L10n.string(appModel.microphoneEnabled ? "麦克风开启" : "麦克风关闭"),
                              systemImage: appModel.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            WaveformStrip(
                levels: appModel.waveformLevels,
                isActive: appModel.isRunning,
                tint: appModel.mode.tint
            )
                .frame(height: 70)

            if appModel.currentSession.segments.isEmpty {
                EmptyTranscriptView()
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                TranscriptListView(segments: appModel.currentSession.segments, fontSize: subtitleFontSize)
                    .frame(minHeight: 360)
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var activeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(activeTitle)
                    .font(.system(size: 34, weight: .semibold))
                HStack(spacing: 14) {
                    Text(TimeFormatter.recordingDate(appModel.currentSession.startedAt))
                    Text(appModel.statusMessage)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            RecordingTimerView(startedAt: appModel.currentSession.startedAt, isRunning: appModel.isRunning)
        }
    }

    private var activeTitle: String {
        switch appModel.mode {
        case .call:
            L10n.string("正在通话转录...")
        case .video:
            L10n.string("正在音/视频录音...")
        case .field:
            L10n.string("正在现场沟通...")
        }
    }

    private var activeSurface: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(appModel.mode.title, systemImage: appModel.mode.systemImage)
                    .font(.headline)
                Spacer()
                Toggle(isOn: Binding(
                    get: { appModel.translationEnabled },
                    set: { appModel.setTranslationEnabled($0) }
                )) {
                    Label(L10n.string("翻译"), systemImage: "character.book.closed")
                }
                .toggleStyle(.switch)
                .help(L10n.string(appModel.translationEnabled ? "关闭英译中" : "开启英译中"))

                if appModel.mode.capturesMicrophoneByDefault {
                    Button {
                        appModel.toggleMicrophone()
                    } label: {
                        Label(L10n.string(appModel.microphoneEnabled ? "麦克风开启" : "麦克风关闭"),
                              systemImage: appModel.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            WaveformStrip(
                levels: appModel.waveformLevels,
                isActive: appModel.isRunning,
                tint: appModel.mode.tint
            )
                .frame(height: 70)

            if appModel.currentSession.segments.isEmpty {
                EmptyTranscriptView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TranscriptListView(segments: appModel.currentSession.segments, fontSize: subtitleFontSize)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var bottomBar: some View {
        HStack(spacing: 18) {
            Spacer()

            Button {
                appModel.startSession()
            } label: {
                Label(L10n.string(appModel.isPreparingSession ? "等待模型" : "开始"),
                      systemImage: appModel.isPreparingSession ? "hourglass" : "play.fill")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .tint(appModel.mode.tint)
            .controlSize(.large)
            .disabled(appModel.isPreparingSession)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var activeBottomBar: some View {
        HStack(spacing: 18) {
            Button {
                appModel.toggleSubtitleWindow()
            } label: {
                Label(
                    L10n.string("字幕模式"),
                    systemImage: appModel.subtitleWindowVisible
                        ? "rectangle.on.rectangle.slash"
                        : "rectangle.on.rectangle"
                )
            }
            .buttonStyle(.borderless)

            ForEach(CopyScope.allCases) { scope in
                Button {
                    appModel.copyCurrent(scope)
                } label: {
                    Label(scope.title, systemImage: scope.systemImage)
                }
                .buttonStyle(.borderless)
            }

            if appModel.mode.capturesMicrophoneByDefault {
                Button {
                    appModel.toggleMicrophone()
                } label: {
                    Label(L10n.string(appModel.microphoneEnabled ? "麦克风" : "麦克风关闭"),
                          systemImage: appModel.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Button {
                appModel.stopSession()
            } label: {
                Label(L10n.string(appModel.isEndingSession ? "保存中" : "结束"), systemImage: "stop.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(appModel.isEndingSession)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }
}

struct RecordingTimerView: View {
    let startedAt: Date
    let isRunning: Bool

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
            HStack(spacing: 10) {
                Circle()
                    .fill(isRunning ? .red : .secondary)
                    .frame(width: 12, height: 12)
                Text(TimeFormatter.shortClock(max(0, timeline.date.timeIntervalSince(startedAt))))
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: Capsule())
        }
    }
}

struct ModeCard: View {
    let mode: CommunicationMode
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(mode.tint)
                .frame(width: 64, height: 64)
                .background(mode.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(mode.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(mode.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 242, alignment: .leading)
        .padding(24)
        .background(isSelected ? mode.tint.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? mode.tint.opacity(0.65) : Color.clear, lineWidth: 1.5)
        }
    }
}

struct WaveformStrip: View {
    let levels: [Double]
    let isActive: Bool
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let displayedLevels = levels.isEmpty ? [0] : levels
            let midY = size.height / 2
            let color = tint.opacity(isActive ? 0.9 : 0.35)
            for (index, level) in displayedLevels.enumerated() {
                let denominator = max(1, displayedLevels.count - 1)
                let x = CGFloat(index) / CGFloat(denominator) * size.width
                let normalized = min(1, max(0, level))
                let height = max(4, CGFloat(normalized) * size.height * 0.86)
                var path = Path()
                path.move(to: CGPoint(x: x, y: midY - height / 2))
                path.addLine(to: CGPoint(x: x, y: midY + height / 2))
                context.stroke(path, with: .color(color), lineWidth: 2)
            }
        }
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyTranscriptView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(L10n.string("转录内容会显示在这里", language: appModel.interfaceLanguage))
                .font(.headline)
            Text(L10n.string(
                "首次使用请在设置中检查 Python 环境和模型目录。",
                language: appModel.interfaceLanguage
            ))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TranscriptListView: View {
    private static let bottomAnchorID = "transcript-scroll-bottom"

    let segments: [TranscriptSegment]
    let fontSize: Double
    @State private var shouldAutoScroll = true
    @State private var isAtBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(segments) { segment in
                        TranscriptSegmentView(segment: segment, fontSize: fontSize)
                            .id(segment.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .padding(.vertical, 8)
            }
            .background(
                ScrollStateObserver(isAtBottom: $isAtBottom) { userReachedBottom in
                    shouldAutoScroll = userReachedBottom
                }
            )
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: segments) {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard shouldAutoScroll, !segments.isEmpty else { return }
        DispatchQueue.main.async {
            guard shouldAutoScroll else { return }
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            DispatchQueue.main.async {
                guard shouldAutoScroll else { return }
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }
}

struct TranscriptSegmentView: View {
    @EnvironmentObject private var appModel: AppModel
    let segment: TranscriptSegment
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(segment.channel.color)
                    .frame(width: 8, height: 8)
                Text(L10n.string(segment.speaker, language: appModel.interfaceLanguage))
                Text(segment.timestamp)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if !segment.sourceText.isEmpty {
                Text(segment.sourceText)
                    .font(.system(
                        size: TranscriptTypography.sourceSize(for: fontSize),
                        weight: .regular
                    ))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            if !segment.translatedText.isEmpty {
                Text(segment.translatedText)
                    .font(.system(
                        size: TranscriptTypography.translationSize(for: fontSize),
                        weight: .medium
                    ))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: segment.translatedText)
    }
}
