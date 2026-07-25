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
            StatusPill(isRunning: appModel.isRunning, isPreparing: appModel.isPreparingSession)
        }
    }

    private var setupTitle: String {
        if appModel.isPreparingSession {
            return "正在准备流式转录..."
        }
        return "选择一种沟通场景"
    }

    private var modeGrid: some View {
        HStack(spacing: 18) {
            ForEach(CommunicationMode.allCases) { mode in
                Button {
                    appModel.setMode(mode)
                } label: {
                    ModeCard(mode: mode, isSelected: appModel.mode == mode)
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
                        Label(appModel.microphoneEnabled ? "麦克风开启" : "麦克风关闭",
                              systemImage: appModel.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            WaveformStrip(isActive: appModel.isRunning, tint: appModel.mode.tint)
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
            "正在通话转录..."
        case .video:
            "正在音/视频录音..."
        case .field:
            "正在现场沟通..."
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
                    Label("翻译", systemImage: "character.book.closed")
                }
                .toggleStyle(.switch)
                .help(appModel.translationEnabled ? "关闭英译中" : "开启英译中")

                if appModel.mode.capturesMicrophoneByDefault {
                    Button {
                        appModel.toggleMicrophone()
                    } label: {
                        Label(appModel.microphoneEnabled ? "麦克风开启" : "麦克风关闭",
                              systemImage: appModel.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            WaveformStrip(isActive: appModel.isRunning, tint: appModel.mode.tint)
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
                Label(appModel.isPreparingSession ? "加载模型" : "开始",
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
                Label("字幕模式", systemImage: appModel.subtitleWindowVisible ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle")
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
                    Label(appModel.microphoneEnabled ? "麦克风" : "麦克风关闭",
                          systemImage: appModel.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Button {
                appModel.stopSession()
            } label: {
                Label(appModel.isEndingSession ? "保存中" : "结束", systemImage: "stop.fill")
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

struct StatusPill: View {
    let isRunning: Bool
    let isPreparing: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 12, height: 12)
                .shadow(color: indicatorColor.opacity(isRunning || isPreparing ? 0.4 : 0), radius: 8)
            Text(statusText)
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: Capsule())
    }

    private var indicatorColor: Color {
        if isRunning { return .red }
        if isPreparing { return .orange }
        return .secondary
    }

    private var statusText: String {
        if isRunning { return "录制中" }
        if isPreparing { return "加载中" }
        return "待机"
    }
}

struct WaveformStrip: View {
    let isActive: Bool
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !isActive)) { timeline in
            Canvas { context, size in
                let columns = 90
                let midY = size.height / 2
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let color = tint.opacity(isActive ? 0.9 : 0.35)
                for index in 0..<columns {
                    let x = CGFloat(index) / CGFloat(columns - 1) * size.width
                    let wave = abs(sin(Double(index) * 0.42 + phase * 4.0))
                    let height = CGFloat(8 + wave * 46)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: midY - height / 2))
                    path.addLine(to: CGPoint(x: x, y: midY + height / 2))
                    context.stroke(path, with: .color(color), lineWidth: 2)
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyTranscriptView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("转录内容会显示在这里")
                .font(.headline)
            Text("首次使用请在设置中检查 Python 环境和模型目录。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TranscriptListView: View {
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
                }
                .padding(.vertical, 8)
            }
            .background(ScrollStateObserver(isAtBottom: $isAtBottom))
            .onChange(of: isAtBottom) {
                shouldAutoScroll = isAtBottom
            }
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: segments) {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard shouldAutoScroll, segments.last != nil else { return }
        DispatchQueue.main.async {
            if let last = segments.last {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(segment.channel.color)
                    .frame(width: 8, height: 8)
                Text(segment.speaker)
                Text(segment.timestamp)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if !segment.sourceText.isEmpty {
                Text(segment.sourceText)
                    .font(.system(size: max(14, fontSize * 0.82), weight: .regular))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            if !segment.translatedText.isEmpty {
                Text(segment.translatedText)
                    .font(.system(size: max(16, fontSize * 0.94), weight: .medium))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: segment.translatedText)
    }
}
