import SwiftUI

/// Main content view — sidebar navigation for different tool features
struct ContentView: View {
    @State private var selectedFeature: Feature = .ssh
    @State private var featureOrder: [Feature] = {
        if let saved = UserDefaults.standard.array(forKey: "sidebarOrder") as? [String] {
            let mapped = saved.compactMap { Feature(rawValue: $0) }.filter { $0 != .settings }
            let remaining = Feature.toolCases.filter { !mapped.contains($0) }
            return mapped + remaining
        }
        return Feature.toolCases
    }()

    enum Feature: String, CaseIterable, Identifiable {
        case ssh = "SSH 管理"
        case ports = "端口占用"
        case env = "环境变量"
        case json = "JSON 工具"
        case codec = "编解码"
        case hiddenFiles = "隐藏文件"
        case proxy = "网络代理"
        case settings = "设置"

        var id: String { rawValue }

        /// Features shown in the draggable sidebar list (excludes settings)
        static var toolCases: [Feature] {
            allCases.filter { $0 != .settings }
        }

        var icon: String {
            switch self {
            case .ssh: return "key.fill"
            case .ports: return "network"
            case .env: return "terminal.fill"
            case .json: return "curlybraces"
            case .codec: return "lock.rotation"
            case .hiddenFiles: return "eye.slash.fill"
            case .proxy: return "network.badge.shield.half.filled"
            case .settings: return "gearshape"
            }
        }

        var description: String {
            switch self {
            case .ssh: return "管理 SSH 密钥与配置"
            case .ports: return "查看端口占用 / 杀进程"
            case .env: return "环境变量与 Profile"
            case .json: return "JSON 格式化 / 压缩"
            case .codec: return "Base64 / URL / JWT / Hash"
            case .hiddenFiles: return "显示/隐藏 dotfiles"
            case .proxy: return "查看/关闭系统代理"
            case .settings: return "版本信息与偏好设置"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedFeature) {
                    ForEach(featureOrder) { feature in
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
                    .onMove { source, destination in
                        featureOrder.move(fromOffsets: source, toOffset: destination)
                        UserDefaults.standard.set(featureOrder.map(\.rawValue), forKey: "sidebarOrder")
                    }
                }
                .listStyle(.sidebar)

                Divider()

                Button {
                    selectedFeature = .settings
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: Feature.settings.icon)
                            .font(.system(size: 13))
                            .foregroundColor(selectedFeature == .settings ? .accentColor : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Feature.settings.rawValue)
                                .font(.system(size: 13))
                            Text(Feature.settings.description)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedFeature == .settings ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .foregroundColor(selectedFeature == .settings ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            switch selectedFeature {
            case .ssh:
                SSHMainView()
            case .ports:
                PortManagerView()
            case .env:
                EnvManagerView()
            case .json:
                JSONToolsView()
            case .codec:
                CodecToolsView()
            case .hiddenFiles:
                HiddenFilesMainView()
            case .proxy:
                ProxyMainView()
            case .settings:
                SettingsView()
            }
        }
        .navigationTitle("DevPal")
    }
}
