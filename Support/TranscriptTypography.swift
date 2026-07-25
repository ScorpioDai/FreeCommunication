import Foundation

enum TranscriptTypography {
    static func sourceSize(for baseSize: CGFloat) -> CGFloat {
        max(14, baseSize * 0.82)
    }

    static func translationSize(for baseSize: CGFloat) -> CGFloat {
        max(16, baseSize * 0.94)
    }
}
