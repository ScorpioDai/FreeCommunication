import AppKit
import Foundation

enum FilePanelService {
    @MainActor
    static func chooseDirectory(initialPath: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let initialPath, !initialPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: initialPath, isDirectory: true)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseMediaFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .quickTimeMovie]
        return panel.runModal() == .OK ? panel.url : nil
    }
}
