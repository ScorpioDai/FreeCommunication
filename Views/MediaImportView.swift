import SwiftUI

struct MediaImportView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("上传英语音视频")
                    .font(.system(size: 32, weight: .semibold))
                Text("支持常见音频和视频格式，后端会用 ffmpeg 转成 16kHz 音频后再转录。")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ImportActionCard(
                    title: "转录",
                    subtitle: "只生成英文原文记录",
                    systemImage: "text.bubble",
                    tint: .blue
                ) {
                    appModel.processSelectedMedia(translate: false)
                }

                ImportActionCard(
                    title: "转录+翻译",
                    subtitle: "生成 txt 与 srt 字幕文件",
                    systemImage: "character.book.closed",
                    tint: .green
                ) {
                    appModel.processSelectedMedia(translate: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("输出位置", systemImage: "folder")
                    .font(.headline)
                Button {
                    appModel.openRecordingsDirectory()
                } label: {
                    HStack {
                        Text(Defaults.recordingsDirectory.path)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if appModel.isProcessingFile {
                ProgressView(appModel.statusMessage)
                    .controlSize(.large)
                    .padding(.top, 8)
            } else {
                Label(appModel.statusMessage, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(30)
    }
}

struct ImportActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 30))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
