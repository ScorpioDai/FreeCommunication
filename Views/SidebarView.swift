import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var selection: SidebarSection

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarSection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .id(appModel.interfaceLanguage)
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("FreeCommunication")
                    .font(.headline)
                    .lineLimit(1)
                Text(L10n.string("本地英文转录与中文翻译"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 210)
    }
}
