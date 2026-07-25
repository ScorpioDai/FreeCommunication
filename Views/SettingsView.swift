import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(Defaults.subtitleOpacityKey) private var subtitleOpacity = 0.74
    @AppStorage(Defaults.subtitleFontSizeKey) private var subtitleFontSize = 24.0
    @AppStorage(Defaults.liveChunkSecondsKey) private var liveChunkSeconds = 3.0
    @AppStorage(Defaults.callVoiceProcessingKey) private var callVoiceProcessingEnabled = false

    var body: some View {
        TabView(selection: $appModel.settingsTab) {
            Form {
                Section("本地模型") {
                    ForEach(ManagedModel.allCases) { model in
                        ModelSettingsRow(model: model)
                            .environmentObject(appModel)
                    }
                }

                Section("模型目录") {
                    LabeledContent("固定位置") {
                        HStack(spacing: 10) {
                            Button {
                                appModel.openModelsDirectory()
                            } label: {
                                Label(Defaults.modelsDirectory.path, systemImage: "folder")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .buttonStyle(.plain)
                            .help("在访达中打开")

                            Button {
                                appModel.refreshModelStates()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("刷新模型状态")
                        }
                    }
                    Text("手动下载的模型需保留上方显示的文件夹名称，并放入此目录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("推理后端") {
                    HStack {
                        Button {
                            appModel.checkBackend()
                        } label: {
                            Label("检查后端", systemImage: "stethoscope")
                        }
                        Text(appModel.backendHealth.title)
                            .foregroundStyle(statusColor)
                        Spacer()
                    }
                    Text(appModel.backendHealth.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .tag(SettingsTab.models)
            .tabItem { Label("模型", systemImage: "cpu") }

            Form {
                LabeledContent("记录目录") {
                    Button {
                        appModel.openRecordingsDirectory()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                            Text(Defaults.recordingsDirectory.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .help("在访达中打开")
                }
                Slider(value: $liveChunkSeconds, in: 2...12, step: 1) {
                    Text("实时分片")
                } minimumValueLabel: {
                    Text("2秒")
                } maximumValueLabel: {
                    Text("12秒")
                }
                Text("当前分片：\(Int(liveChunkSeconds)) 秒")
                    .foregroundStyle(.secondary)
                Toggle("通话模式系统回声消除（实验）", isOn: $callVoiceProcessingEnabled)
                Text("默认关闭以保持麦克风原始灵敏度；开启后可能压低电脑声音，适合再次测试系统级回声消除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tag(SettingsTab.recording)
            .tabItem { Label("录制", systemImage: "waveform") }

            Form {
                Slider(value: $subtitleOpacity, in: 0.35...0.95, step: 0.01) {
                    Text("字幕透明度")
                }
                Slider(value: $subtitleFontSize, in: 16...42, step: 1) {
                    Text("字幕字号")
                }
                Text("字幕窗口可以拖动和缩放；鼠标移入时显示控制条。")
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tag(SettingsTab.subtitles)
            .tabItem { Label("字幕", systemImage: "rectangle.on.rectangle") }
        }
        .frame(width: 760, height: 520)
        .padding()
    }

    private var statusColor: Color {
        switch appModel.backendHealth {
        case .ready: .green
        case .warning: .orange
        case .failed: .red
        case .checking: .blue
        case .unknown: .secondary
        }
    }

}

private struct ModelSettingsRow: View {
    @EnvironmentObject private var appModel: AppModel
    let model: ManagedModel

    private var state: ModelInstallState {
        appModel.modelState(for: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.roleTitle)
                        .font(.headline)
                    Text(model.displayName)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusView
            }

            downloadView

            Text(model.directoryURL.path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .missing:
            Label("未安装", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        case .ready:
            Label("已就绪", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading:
            Label("下载中", systemImage: "arrow.down.circle")
                .foregroundStyle(.blue)
        case .failed:
            Label("失败", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var downloadView: some View {
        switch state {
        case .missing:
            Button {
                appModel.download(model)
            } label: {
                Label("从 Hugging Face 下载", systemImage: "arrow.down.circle")
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button {
                    appModel.download(model)
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 5) {
                if progress.totalBytes > 0 {
                    ProgressView(value: progress.fractionCompleted)
                } else {
                    ProgressView()
                }
                HStack {
                    Text(progress.currentFile.isEmpty ? "正在读取仓库清单" : progress.currentFile)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if progress.totalBytes > 0 {
                        Text("\(formattedBytes(progress.completedBytes)) / \(formattedBytes(progress.totalBytes))")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case .checking, .ready:
            EmptyView()
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct InWindowSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置")
                .font(.system(size: 32, weight: .semibold))
            SettingsView()
                .frame(maxWidth: 820, maxHeight: 580, alignment: .leading)
            Spacer()
        }
        .padding(30)
    }
}
