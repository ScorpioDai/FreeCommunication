import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var library: RecordingLibrary
    @StateObject private var player = RecordingAudioPlayer()
    @State private var renameTitle = ""
    @State private var showRename = false

    var body: some View {
        HStack(spacing: 0) {
            recordList
                .frame(width: 320)
                .background(.bar)

            Divider()

            detail
        }
        .task { await library.reload() }
        .sheet(isPresented: $showRename) {
            RenameSheet(title: $renameTitle) {
                if let document = library.selectedDocument() {
                    appModel.rename(document: document, to: renameTitle)
                }
                showRename = false
            }
        }
    }

    private var recordList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("过往记录")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    Task { await library.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                Button {
                    appModel.openRecordingsDirectory()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            List(selection: $library.selection) {
                ForEach(library.documents) { document in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .lineLimit(1)
                        Text(document.displayDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(document.id)
                    .contextMenu {
                        Button("复制原文") { appModel.copy(document: document, scope: .source) }
                        Button("复制译文") { appModel.copy(document: document, scope: .translation) }
                        Button("复制原文+译文") { appModel.copy(document: document, scope: .bilingual) }
                        Divider()
                        Button("在访达中显示") {
                            appModel.reveal(document: document)
                        }
                        Button("重命名") {
                            renameTitle = document.title
                            showRename = true
                        }
                        Button("删除", role: .destructive) {
                            appModel.delete(document: document)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let document = library.selectedDocument() {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(document.title)
                            .font(.system(size: 28, weight: .semibold))
                            .lineLimit(1)
                        Text(document.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Menu {
                        ForEach(CopyScope.allCases) { scope in
                            Button(scope.title) {
                                appModel.copy(document: document, scope: scope)
                            }
                        }
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    Button {
                        appModel.reveal(document: document)
                    } label: {
                        Label("访达", systemImage: "folder")
                    }
                    Button {
                        renameTitle = document.title
                        showRename = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        appModel.delete(document: document)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .padding(24)

                Divider()

                if document.audioURL != nil {
                    RecordingPlayerBar(document: document, player: player)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                    Divider()
                }

                SyncedTranscriptView(document: document, player: player)
            }
            .onChange(of: document.audioURL) { _, newValue in
                player.load(url: newValue)
            }
        } else {
            ContentUnavailableView("暂无记录", systemImage: "doc.text", description: Text("结束实时会话或上传文件后，记录会出现在这里。"))
        }
    }
}

struct RecordingPlayerBar: View {
    let document: RecordingDocument
    @ObservedObject var player: RecordingAudioPlayer

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.seek(by: -10)
            } label: {
                Image(systemName: "gobackward.10")
            }
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderedProminent)
            Button {
                player.seek(by: 10)
            } label: {
                Image(systemName: "goforward.10")
            }

            Text(TimeFormatter.shortClock(player.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )

            Text(TimeFormatter.shortClock(player.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .onAppear { player.load(url: document.audioURL) }
        .onChange(of: document.audioURL) { _, newValue in
            player.load(url: newValue)
        }
    }
}

struct SyncedTranscriptView: View {
    let document: RecordingDocument
    @ObservedObject var player: RecordingAudioPlayer

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if document.segments.isEmpty {
                    Text(document.bilingualText.isEmpty ? document.sourceText : document.bilingualText)
                        .font(.system(size: 18))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(document.segments.enumerated()), id: \.element.id) { index, segment in
                            let active = activeSegmentID == segment.id
                            SegmentBlockView(segment: segment, active: active) {
                                if document.audioURL != nil {
                                    player.load(url: document.audioURL)
                                    player.seek(to: segment.start)
                                }
                            }
                            .id(segment.id)
                        }
                    }
                    .padding(24)
                }
            }
            .onChange(of: activeSegmentID) { _, newValue in
                if let newValue, player.isPlaying {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private var activeSegmentID: TranscriptSegment.ID? {
        guard !document.segments.isEmpty else { return nil }
        let current = player.currentTime
        for (index, segment) in document.segments.enumerated() {
            let nextStart = index + 1 < document.segments.count ? document.segments[index + 1].start : nil
            let end = segment.end ?? nextStart ?? segment.start + max(3.0, Double(segment.sourceText.split(separator: " ").count) * 0.35)
            if current >= segment.start && current < end {
                return segment.id
            }
        }
        return document.segments.last(where: { $0.start <= current })?.id
    }
}

struct SegmentBlockView: View {
    let segment: TranscriptSegment
    let active: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(segment.channel.color)
                    .frame(width: 8, height: 8)
                Text(segment.speaker)
                    .font(.caption.weight(.medium))
                Text(segment.timestamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(segment.sourceText)
                .font(.system(size: 18))
                .foregroundStyle(active ? .blue : .primary)
                .textSelection(.enabled)
            if !segment.translatedText.isEmpty {
                Text(segment.translatedText)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(active ? .blue.opacity(0.82) : .secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Color.blue.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

struct RenameSheet: View {
    @Binding var title: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("重命名记录")
                .font(.title2.weight(.semibold))
            TextField("记录名称", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}
