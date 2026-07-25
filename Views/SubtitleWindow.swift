import AppKit
import SwiftUI

final class SubtitleWindowController: NSWindowController {
    private weak var appModel: AppModel?

    @MainActor
    init(appModel: AppModel) {
        self.appModel = appModel
        let hosting = NSHostingController(rootView: SubtitlePanelView().environmentObject(appModel))
        hosting.sizingOptions = []
        let visibleFrame = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        let width = max(820, min(1320, visibleFrame.width - 64))
        let height: CGFloat = 240
        let origin = CGPoint(x: visibleFrame.midX - width / 2, y: visibleFrame.minY + 28)
        let window = NSPanel(
            contentRect: CGRect(origin: origin, size: CGSize(width: width, height: height)),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.setContentSize(CGSize(width: width, height: height))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = CGSize(width: 720, height: 180)
        window.contentMinSize = CGSize(width: 720, height: 180)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    override func close() {
        super.close()
        Task { @MainActor [weak appModel] in
            appModel?.subtitleWindowVisible = false
        }
    }
}

struct SubtitlePanelView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(Defaults.subtitleOpacityKey) private var opacity = 0.74
    @AppStorage(Defaults.subtitleFontSizeKey) private var fontSize = 24.0
    @State private var isHovering = false
    @State private var shouldAutoScroll = true
    @State private var isAtBottom = true

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(appModel.currentSession.segments) { segment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(segment.sourceText)
                                    .font(.system(size: max(14, fontSize * 0.72)))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(2)
                                if !segment.translatedText.isEmpty {
                                    Text(segment.translatedText)
                                        .font(.system(size: fontSize, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(3)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .animation(.easeInOut(duration: 0.2), value: segment.translatedText)
                            .id(segment.id)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .padding(.bottom, isHovering ? 56 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(ScrollStateObserver(isAtBottom: $isAtBottom))
                .onChange(of: isAtBottom) {
                    shouldAutoScroll = isAtBottom
                }
                .onChange(of: appModel.currentSession.segments.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: appModel.currentSession.segments) {
                    scrollToBottom(proxy)
                }
                .onAppear {
                    scrollToBottom(proxy)
                }
            }

            if isHovering {
                controlBar
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 720, minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(opacity))
        )
        .overlay(alignment: .topTrailing) {
            if appModel.currentSession.segments.isEmpty {
                Text("等待字幕")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(14)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovering = hover
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard shouldAutoScroll, let last = appModel.currentSession.segments.last else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 18) {
            Button {
                appModel.toggleSubtitleWindow()
            } label: {
                Image(systemName: "rectangle.on.rectangle.slash")
            }
            .help("退出字幕模式")

            if appModel.mode.capturesMicrophoneByDefault {
                Button {
                    appModel.toggleMicrophone()
                } label: {
                    Image(systemName: appModel.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                }
                .help(appModel.microphoneEnabled ? "关闭麦克风" : "开启麦克风")
            }

            Button {
                appModel.toggleTranslation()
            } label: {
                Image(systemName: appModel.translationEnabled
                      ? "character.book.closed.fill"
                      : "character.book.closed")
            }
            .help(appModel.translationEnabled ? "关闭英译中" : "开启英译中")

            Label("英语", systemImage: "textformat")
            if appModel.translationEnabled {
                Label("中文", systemImage: "character.book.closed")
                    .transition(.opacity)
            }

            Slider(value: $opacity, in: 0.35...0.95)
                .frame(width: 130)
                .help("透明度")

            Slider(value: $fontSize, in: 16...42)
                .frame(width: 130)
                .help("字号")

            Spacer()

            Button {
                appModel.isRunning ? appModel.stopSession() : appModel.startSession()
            } label: {
                Label(appModel.isRunning ? "结束" : "开始", systemImage: appModel.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(appModel.isRunning ? .red : .green)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.82))
        .animation(.easeInOut(duration: 0.18), value: appModel.translationEnabled)
    }
}
