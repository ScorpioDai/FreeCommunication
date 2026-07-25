import AppKit
import SwiftUI

@main
struct FreeCommunicationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @StateObject private var library = RecordingLibrary()

    init() {
        Defaults.register()
    }

    var body: some Scene {
        WindowGroup("FreeCommunication", id: "main") {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(library)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    appModel.attach(library: library)
                    await library.reload()
                    appModel.checkModelsOnLaunch()
                }
        }
        .commands {
            CommandMenu(L10n.string("转录")) {
                Button(L10n.string(appModel.isRunning ? "结束" : "开始")) {
                    appModel.isRunning ? appModel.stopSession() : appModel.startSession()
                }
                .keyboardShortcut(.space, modifiers: [.command])

                Button(L10n.string("字幕模式")) {
                    appModel.toggleSubtitleWindow()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button(L10n.string(appModel.translationEnabled ? "关闭翻译" : "开启翻译")) {
                    appModel.toggleTranslation()
                }
                .disabled(!appModel.liveSessionActive)

                Divider()

                Button(L10n.string("复制原文")) { appModel.copyCurrent(.source) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button(L10n.string("复制译文")) { appModel.copyCurrent(.translation) }
                Button(L10n.string("复制原文+译文")) { appModel.copyCurrent(.bilingual) }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
