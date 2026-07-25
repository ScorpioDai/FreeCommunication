import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var library: RecordingLibrary

    var body: some View {
        Group {
            if appModel.liveSessionActive {
                LiveView()
            } else {
                NavigationSplitView {
                    SidebarView(selection: $appModel.selection)
                } detail: {
                    Group {
                        switch appModel.selection {
                        case .live:
                            LiveView()
                        case .files:
                            MediaImportView()
                        case .records:
                            RecordsView()
                        case .settings:
                            InWindowSettingsView()
                        }
                    }
                    .navigationTitle(appModel.selection.title)
                }
            }
        }
        .alert("需要安装模型", isPresented: $appModel.showMissingModelsAlert) {
            Button("稍后", role: .cancel) {
                appModel.showMissingModelsAlert = false
            }
            Button("下载模型") {
                appModel.beginMissingModelDownloads()
            }
        } message: {
            Text("实时转录需要语音识别与英译中模型。是否前往设置并从 Hugging Face 下载？")
        }
    }
}
