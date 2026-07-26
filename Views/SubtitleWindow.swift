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
    private static let bottomAnchorID = "subtitle-scroll-bottom"

    @EnvironmentObject private var appModel: AppModel
    @AppStorage(Defaults.subtitleOpacityKey) private var opacity = 0.74
    @AppStorage(Defaults.subtitleFontSizeKey) private var fontSize = 24.0
    @State private var isHovering = false
    @State private var shouldAutoScroll = true
    @State private var isAtBottom = true
    @State private var userHasTakenScrollControl = false

    var body: some View {
        VStack(spacing: 2) {
            subtitleSurface

            controlBar
                .frame(height: 40)
                .opacity(isHovering ? 1 : 0)
                .offset(y: isHovering ? 0 : -4)
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
                                            size: TranscriptTypography.sourceSize(for: fontSize),
                                            weight: .medium
                                        ))
                                        .foregroundStyle(.white)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .animation(.easeInOut(duration: 0.2), value: segment.translatedText)
                            .id(segment.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .autoFollowScrollState(
                    isEnabled: $shouldAutoScroll,
                    isAtBottom: $isAtBottom,
                    userHasTakenControl: $userHasTakenScrollControl
                )
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
        guard shouldAutoScroll, !appModel.currentSession.segments.isEmpty else { return }
        DispatchQueue.main.async {
            guard shouldAutoScroll else { return }
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            DispatchQueue.main.async {
                guard shouldAutoScroll else { return }
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                appModel.toggleSubtitleWindow()
            } label: {
                Image(systemName: "rectangle.on.rectangle.slash")
            }
            .help(L10n.string("退出字幕模式"))

            Button {
                appModel.toggleMainWindowVisibility()
            } label: {
                ZStack {
                    Image(systemName: "macwindow")
                    if !appModel.mainWindowVisibleInSubtitle {
                        DisabledSlash()
                    }
                }
                .frame(width: 22, height: 20)
            }
            .help(
                L10n.string(
                    appModel.mainWindowVisibleInSubtitle ? "隐藏主界面" : "显示主界面"
                )
            )

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
                        DisabledSlash()
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
            WedgeSlider(value: $opacity, range: 0.35...0.95)
                .frame(width: 92)
                .help(L10n.string("透明度"))
                .accessibilityLabel(Text(L10n.string("透明度")))

            Image(systemName: "textformat.size")
                .help(L10n.string("字号"))
            WedgeSlider(value: $fontSize, range: 16...42)
                .frame(width: 92)
                .help(L10n.string("字号"))
                .accessibilityLabel(Text(L10n.string("字号")))

            Button {
                appModel.isRunning ? appModel.stopSession() : appModel.startSession()
            } label: {
                Label(
                    L10n.string(appModel.isRunning ? "结束" : "开始"),
                    systemImage: appModel.isRunning ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        appModel.isRunning
                            ? Color.red.opacity(0.42)
                            : Color.green.opacity(0.38)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        appModel.isRunning
                            ? Color.red.opacity(0.55)
                            : Color.green.opacity(0.48),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(opacity))
        )
        .animation(.easeInOut(duration: 0.18), value: appModel.translationEnabled)
        .animation(.easeInOut(duration: 0.18), value: appModel.mainWindowVisibleInSubtitle)
        .onHover { hover in
            setPanelMovementEnabled(!hover)
        }
        .onDisappear {
            setPanelMovementEnabled(true)
        }
    }

    private func setPanelMovementEnabled(_ enabled: Bool) {
        let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }
        panel?.isMovableByWindowBackground = enabled
    }
}

private struct DisabledSlash: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.72))
            .frame(width: 23, height: 2.4)
            .rotationEffect(.degrees(45))
            .shadow(color: .black.opacity(0.7), radius: 0.5)
    }
}

private struct WedgeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let knobDiameter: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let usableWidth = max(1, width - knobDiameter)
            let knobCenter = knobDiameter / 2 + usableWidth * fraction

            ZStack(alignment: .leading) {
                WedgeTrack()
                    .fill(Color.white.opacity(0.18))

                WedgeTrack()
                    .fill(Color.white.opacity(0.48))
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: knobCenter)
                    }

                Circle()
                    .fill(Color.white)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                    .offset(x: knobCenter - knobDiameter / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let position = min(
                            max(gesture.location.x - knobDiameter / 2, 0),
                            usableWidth
                        )
                        setFraction(Double(position / usableWidth))
                    }
            )
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(fraction * 100))%"))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment:
                value = min(range.upperBound, value + step)
            case .decrement:
                value = max(range.lowerBound, value - step)
            @unknown default:
                break
            }
        }
    }

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private func setFraction(_ fraction: Double) {
        value = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}

private struct WedgeTrack: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 2))
        path.closeSubpath()
        return path
    }
}
