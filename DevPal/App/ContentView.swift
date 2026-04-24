import SwiftUI

/// Main content view — sidebar navigation for different tool features
struct ContentView: View {
    @State private var selectedFeature: Feature = .ssh

    enum Feature: String, CaseIterable, Identifiable {
        case ssh = "SSH 管理"
        case hiddenFiles = "隐藏文件"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .ssh: return "key.fill"
            case .hiddenFiles: return "eye.slash.fill"
            }
        }

        var description: String {
            switch self {
            case .ssh: return "管理 SSH 密钥与配置"
            case .hiddenFiles: return "显示/隐藏 dotfiles"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: $selectedFeature) { feature in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.rawValue)
                            .font(.system(size: 13))
                        Text(feature.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: feature.icon)
                        .foregroundColor(.accentColor)
                }
                .tag(feature)
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            switch selectedFeature {
            case .ssh:
                SSHMainView()
            case .hiddenFiles:
                HiddenFilesMainView()
            }
        }
        .navigationTitle("DevPal")
    }
}
