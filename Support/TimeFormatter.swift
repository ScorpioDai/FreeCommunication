import Foundation

enum TimeFormatter {
    private static let recordingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter
    }()

    static func recordingName(for date: Date = Date()) -> String {
        recordingFormatter.string(from: date)
    }

    static func recordingDate(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    static func shortClock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func srtClock(_ interval: TimeInterval) -> String {
        let milliseconds = max(0, Int((interval * 1000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let seconds = (milliseconds % 60_000) / 1000
        let ms = milliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, ms)
    }
}
