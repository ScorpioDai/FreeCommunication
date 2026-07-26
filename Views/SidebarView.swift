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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                ForEach(ManagedModel.allCases) { model in
                    SidebarModelStatusView(model: model)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 210)
    }
}

private struct SidebarModelStatusView: View {
    @EnvironmentObject private var appModel: AppModel
    let model: ManagedModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(model.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(model.displayName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsActivity {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusTitle: String {
        switch appModel.modelState(for: model) {
        case .checking:
            return L10n.string("正在检查模型")
        case .missing:
            return L10n.string("模型未下载")
        case .downloading(let progress):
            return L10n.format(
                "正在下载 · %d%%",
                Int(progress.fractionCompleted * 100)
            )
        case .failed:
            return L10n.string("模型下载失败")
        case .ready:
            switch appModel.runtimeModelState(for: model) {
            case .unavailable:
                return L10n.string("等待模型加载")
            case .loading:
                return L10n.string("正在加载模型")
            case .ready:
                return L10n.string("模型已就绪")
            case .failed:
                return L10n.string("模型加载失败")
            }
        }
    }

    private var indicatorColor: Color {
        switch appModel.modelState(for: model) {
        case .checking, .missing:
            return .secondary
        case .downloading:
            return .yellow
        case .failed:
            return .red
        case .ready:
            switch appModel.runtimeModelState(for: model) {
            case .unavailable:
                return .secondary
            case .loading:
                return .yellow
            case .ready:
                return .green
            case .failed:
                return .red
            }
        }
    }

    private var showsActivity: Bool {
        switch appModel.modelState(for: model) {
        case .checking, .downloading:
            return true
        case .missing, .failed:
            return false
        case .ready:
            return appModel.runtimeModelState(for: model) == .loading
        }
    }
}
