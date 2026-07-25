import Foundation
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case live
    case files
    case records
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "实时"
        case .files: "音视频"
        case .records: "记录"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .live: "waveform.and.mic"
        case .files: "tray.and.arrow.up"
        case .records: "doc.text"
        case .settings: "gearshape"
        }
    }
}

enum CommunicationMode: String, CaseIterable, Identifiable, Codable {
    case call
    case video
    case field

    var id: String { rawValue }

    var title: String {
        switch self {
        case .call: "通话模式"
        case .video: "视频模式"
        case .field: "现场模式"
        }
    }

    var subtitle: String {
        switch self {
        case .call: "同时捕捉系统声音与麦克风"
        case .video: "仅捕捉英语视频或会议外放声音"
        case .field: "仅捕捉本机麦克风"
        }
    }

    var systemImage: String {
        switch self {
        case .call: "phone.connection"
        case .video: "speaker.wave.2"
        case .field: "mic"
        }
    }

    var tint: Color {
        switch self {
        case .call: .green
        case .video: .blue
        case .field: .red
        }
    }

    var capturesMicrophoneByDefault: Bool {
        switch self {
        case .call, .field: true
        case .video: false
        }
    }

    var capturesSystemAudio: Bool {
        switch self {
        case .call, .video: true
        case .field: false
        }
    }
}

enum CopyScope: String, CaseIterable, Identifiable {
    case source
    case translation
    case bilingual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: "复制原文"
        case .translation: "复制译文"
        case .bilingual: "复制原文+译文"
        }
    }

    var systemImage: String {
        switch self {
        case .source: "text.quote"
        case .translation: "character.book.closed"
        case .bilingual: "doc.on.doc"
        }
    }
}

enum SegmentChannel: String, Codable, Sendable {
    case microphone
    case system
    case file

    var speaker: String {
        switch self {
        case .microphone: "我"
        case .system: "电脑音频"
        case .file: "音频"
        }
    }

    var color: Color {
        switch self {
        case .microphone: .green
        case .system: .yellow
        case .file: .blue
        }
    }
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    var id = UUID()
    var channel: SegmentChannel
    var speaker: String
    var start: TimeInterval
    var end: TimeInterval?
    var sourceText: String
    var translatedText: String
    var isFinal: Bool

    var timestamp: String {
        TimeFormatter.shortClock(start)
    }
}

struct TranscriptSession: Identifiable {
    let id = UUID()
    var mode: CommunicationMode
    var startedAt: Date
    var endedAt: Date?
    var title: String
    var segments: [TranscriptSegment] = []

    var elapsed: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var sourceText: String {
        segments.map(\.sourceText).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var translatedText: String {
        segments.map(\.translatedText).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var bilingualText: String {
        segments.map { segment in
            var parts: [String] = []
            if !segment.sourceText.isEmpty {
                parts.append(segment.sourceText)
            }
            if !segment.translatedText.isEmpty {
                parts.append(segment.translatedText)
            }
            return parts.joined(separator: "\n")
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }
}

struct RecordingDocument: Identifiable, Hashable {
    let id: URL
    var url: URL
    var containerURL: URL
    var audioURL: URL?
    var srtURL: URL?
    var title: String
    var createdAt: Date
    var sourceText: String
    var translatedText: String
    var bilingualText: String
    var segments: [TranscriptSegment]

    var isFolderBacked: Bool {
        containerURL != url
    }

    var displayDate: String {
        TimeFormatter.recordingDate(createdAt)
    }
}

enum BackendHealth: Equatable {
    case unknown
    case checking
    case ready(String)
    case warning(String)
    case failed(String)

    var title: String {
        switch self {
        case .unknown: "未检查"
        case .checking: "检查中"
        case .ready: "后端可用"
        case .warning: "需要注意"
        case .failed: "不可用"
        }
    }

    var message: String {
        switch self {
        case .unknown: "尚未检查模型与 Python 环境。"
        case .checking: "正在检查模型目录、ffmpeg 与 Python 依赖。"
        case .ready(let message), .warning(let message), .failed(let message):
            message
        }
    }
}
