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
        private var eventMonitor: Any?
        private var userIsInteracting = false

        init(isAtBottom: Binding<Bool>, onUserScroll: ((Bool) -> Void)?) {
            self.isAtBottom = isAtBottom
            self.onUserScroll = onUserScroll
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
        }

        func attach(to scrollView: NSScrollView?) {
            guard let scrollView, self.scrollView !== scrollView else { return }
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.handleBoundsChange()
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                updateState()
                onUserScroll?(reachedBottom())
            })
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                self?.handleUserInput(event)
                return event
            }
            updateState()
        }

        private func handleBoundsChange() {
            updateState()
            if userIsInteracting {
                onUserScroll?(reachedBottom())
            }
        }

        private func handleUserInput(_ event: NSEvent) {
            guard let scrollView, event.window === scrollView.window else { return }
            let location = scrollView.convert(event.locationInWindow, from: nil)

            switch event.type {
            case .scrollWheel:
                guard scrollView.bounds.contains(location) else { return }
                userIsInteracting = true
                onUserScroll?(false)
            case .leftMouseDown, .leftMouseDragged:
                guard let scroller = scrollView.verticalScroller,
                      !scroller.isHidden,
                      scroller.frame.contains(location) else { return }
                userIsInteracting = true
                onUserScroll?(false)
            case .leftMouseUp:
                guard userIsInteracting else { return }
                onUserScroll?(reachedBottom())
                userIsInteracting = false
            default:
                break
            }
        }

        private func updateState() {
            guard let remainingDistance = remainingDistanceToBottom() else { return }
            let nearBottom = remainingDistance < 36
            if isAtBottom.wrappedValue != nearBottom {
                isAtBottom.wrappedValue = nearBottom
            }
        }

        private func reachedBottom() -> Bool {
            if let scroller = scrollView?.verticalScroller {
                if scroller.knobProportion >= 0.999 {
                    return true
                }
                return scroller.doubleValue >= 0.999
            }
            guard let remainingDistance = remainingDistanceToBottom() else { return true }
            return remainingDistance <= 2
        }

        private func remainingDistanceToBottom() -> CGFloat? {
            guard let scrollView, let documentView = scrollView.documentView else { return nil }
            let visibleBounds = scrollView.contentView.bounds
            let documentBounds = documentView.bounds
            if documentView.isFlipped {
                return max(0, documentBounds.maxY - visibleBounds.maxY)
            }
            return max(0, visibleBounds.minY - documentBounds.minY)
        }
    }
}
