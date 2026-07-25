import AppKit
import SwiftUI

struct ScrollStateObserver: NSViewRepresentable {
    @Binding var isAtBottom: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isAtBottom: $isAtBottom)
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
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.enclosingScrollView)
        }
    }

    final class Coordinator {
        var isAtBottom: Binding<Bool>
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?

        init(isAtBottom: Binding<Bool>) {
            self.isAtBottom = isAtBottom
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(to scrollView: NSScrollView?) {
            guard let scrollView, self.scrollView !== scrollView else { return }
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateState()
            }
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
