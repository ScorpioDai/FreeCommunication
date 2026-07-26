import SwiftUI

extension View {
    func autoFollowScrollState(
        isEnabled: Binding<Bool>,
        isAtBottom: Binding<Bool>,
        userHasTakenControl: Binding<Bool>
    ) -> some View {
        modifier(AutoFollowScrollStateModifier(
            isEnabled: isEnabled,
            isAtBottom: isAtBottom,
            userHasTakenControl: userHasTakenControl
        ))
    }
}

private struct AutoFollowScrollStateModifier: ViewModifier {
    @Binding var isEnabled: Bool
    @Binding var isAtBottom: Bool
    @Binding var userHasTakenControl: Bool

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                Self.isAtBottom(geometry)
            } action: { _, reachedBottom in
                isAtBottom = reachedBottom
                if userHasTakenControl, reachedBottom {
                    userHasTakenControl = false
                    isEnabled = true
                }
            }
            .onScrollPhaseChange { _, newPhase, context in
                switch newPhase {
                case .tracking, .interacting, .decelerating:
                    userHasTakenControl = true
                    isEnabled = false
                case .idle:
                    guard userHasTakenControl else { return }
                    let reachedBottom = Self.isAtBottom(context.geometry)
                    isAtBottom = reachedBottom
                    if reachedBottom {
                        userHasTakenControl = false
                        isEnabled = true
                    }
                case .animating:
                    break
                }
            }
    }

    private static func isAtBottom(_ geometry: ScrollGeometry) -> Bool {
        let contentFits = geometry.contentSize.height <= geometry.containerSize.height + 2
        return contentFits || geometry.visibleRect.maxY >= geometry.contentSize.height - 2
    }
}
