import AppKit
import SwiftUI

struct ScrollStateObserver: NSViewRepresentable {
    @Binding var isAtBottom: Bool
    var onUserScroll: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(isAtBottom: $isAtBottom, onUserScroll: onUserScroll)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.enclosingScrollView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isAtBottom = $isAtBottom
        context.coordinator.onUserScroll = onUserScroll
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.enclosingScrollView)
        }
    }

    final class Coordinator {
        var isAtBottom: Binding<Bool>
        var onUserScroll: ((Bool) -> Void)?
        private weak var scrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []

        init(isAtBottom: Binding<Bool>, onUserScroll: ((Bool) -> Void)?) {
            self.isAtBottom = isAtBottom
            self.onUserScroll = onUserScroll
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(to scrollView: NSScrollView?) {
            guard let scrollView, self.scrollView !== scrollView else { return }
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateState()
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                updateState()
                onUserScroll?(isAtBottom.wrappedValue)
            })
            updateState()
        }

        private func updateState() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let visibleMaxY = scrollView.contentView.bounds.maxY
            let contentHeight = documentView.bounds.height
            let nearBottom = contentHeight - visibleMaxY < 36
            if isAtBottom.wrappedValue != nearBottom {
                isAtBottom.wrappedValue = nearBottom
            }
        }
    }
}
