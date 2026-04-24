import SwiftUI

/// Main content view — sidebar navigation for different tool features
struct ContentView: View {
    @State private var selectedFeature: Feature = .ssh

    enum Feature: String, CaseIterable, Identifiable {
        case ssh = "SSH 管理"
        // Future features:
        // case json = "JSON 工具"
        // case regex = "正则测试"
        // case hash = "哈希生成"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .ssh: return "key.fill"
            }
        }

        var description: String {
            switch self {
            case .ssh: return "管理 SSH 密钥与配置"
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
            }
        }
        .navigationTitle("DevPal")
    }
}
