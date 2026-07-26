import AppKit
import SwiftUI

final class SubtitleWindowController: NSWindowController, NSWindowDelegate {
    private weak var appModel: AppModel?
    private static let minimumSize = CGSize(width: 900, height: 200)

    @MainActor
    init(appModel: AppModel) {
        self.appModel = appModel
        let hosting = NSHostingController(rootView: SubtitlePanelView().environmentObject(appModel))
        hosting.sizingOptions = []
        let visibleFrame = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        let width = max(900, min(1060, visibleFrame.width - 96))
        let height: CGFloat = 228
        let origin = CGPoint(x: visibleFrame.midX - width / 2, y: visibleFrame.minY + 10)
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
        window.minSize = Self.minimumSize
        window.contentMinSize = Self.minimumSize
        super.init(window: window)
        window.delegate = self
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

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(Self.minimumSize.width, frameSize.width),
            height: max(Self.minimumSize.height, frameSize.height)
        )
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
        VStack(spacing: 6) {
            subtitleSurface

            controlBar
                .frame(height: 48)
                .opacity(isHovering ? 1 : 0)
                .offset(y: isHovering ? 0 : -8)
                .allowsHitTesting(isHovering)
        }
        .frame(minWidth: 900, minHeight: 200)
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hover
            }
        }
        .environment(\.locale, appModel.interfaceLanguage.locale)
    }

    private var subtitleSurface: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(appModel.currentSession.segments) { segment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(segment.sourceText)
                                    .font(.system(
                                        size: TranscriptTypography.sourceSize(for: fontSize),
                                        weight: .regular
                                    ))
                                    .foregroundStyle(.white.opacity(0.72))
                                if !segment.translatedText.isEmpty {
                                    Text(segment.translatedText)
                                        .font(.system(
                                            size: TranscriptTypography.translationSize(for: fontSize),
                                            weight: .medium
                                        ))
                                        .foregroundStyle(.white)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .animation(.easeInOut(duration: 0.2), value: segment.translatedText)
                            .id(segment.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
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

            if appModel.currentSession.segments.isEmpty {
                Text(L10n.string("等待字幕"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(opacity))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
        HStack(spacing: 14) {
            Button {
                appModel.toggleSubtitleWindow()
            } label: {
                Image(systemName: "rectangle.on.rectangle.slash")
            }
            .help(L10n.string("退出字幕模式"))

            Button {
                appModel.showMainWindow()
            } label: {
                Image(systemName: "macwindow")
            }
            .help(L10n.string("显示主界面"))

            if appModel.mode.capturesMicrophoneByDefault {
                Button {
                    appModel.toggleMicrophone()
                } label: {
                    Image(systemName: appModel.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                }
            .help(L10n.string(appModel.microphoneEnabled ? "关闭麦克风" : "开启麦克风"))
            }

            Button {
                appModel.toggleTranslation()
            } label: {
                ZStack {
                    Image(systemName: "translate")
                    if !appModel.translationEnabled {
                        Capsule()
                            .fill(Color.red)
                            .frame(width: 22, height: 2.5)
                            .rotationEffect(.degrees(-45))
                            .shadow(color: .black.opacity(0.9), radius: 0.5)
                    }
                }
                .frame(width: 22, height: 20)
            }
            .help(L10n.string(appModel.translationEnabled ? "关闭英译中" : "开启英译中"))
            .accessibilityLabel(
                L10n.string(appModel.translationEnabled ? "关闭英译中" : "开启英译中")
            )

            Divider()
                .frame(height: 18)

            Text(L10n.string("原文：英语"))
            if appModel.translationEnabled {
                Text(L10n.string("译文：中文"))
                    .transition(.opacity)
            }

            Spacer(minLength: 8)

            Image(systemName: "circle.lefthalf.filled")
                .help(L10n.string("透明度"))
            Slider(value: $opacity, in: 0.35...0.95)
                .frame(width: 70)
                .help(L10n.string("透明度"))

            Image(systemName: "textformat.size")
                .help(L10n.string("字号"))
            Slider(value: $fontSize, in: 16...42)
                .frame(width: 70)
                .help(L10n.string("字号"))

            Button {
                appModel.isRunning ? appModel.stopSession() : appModel.startSession()
            } label: {
                Label(
                    L10n.string(appModel.isRunning ? "结束" : "开始"),
                    systemImage: appModel.isRunning ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(appModel.isRunning ? .red : .green)
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.84))
        )
        .animation(.easeInOut(duration: 0.18), value: appModel.translationEnabled)
    }
}
