import SwiftUI

/// Main SSH feature view with tab navigation
struct SSHMainView: View {
    @StateObject private var viewModel = SSHViewModel()
    @State private var selectedTab: SSHTab = .keys

    enum SSHTab: String, CaseIterable {
        case keys = "密钥管理"
        case config = "Host 配置"
        case test = "连通测试"
        case repos = "仓库扫描"
        case knownHosts = "known_hosts"
        case identity = "Git 身份"
        case source = "源码模式"
        case backup = "备份恢复"
        case guide = "帮助文档"

        var icon: String {
            switch self {
            case .keys: return "key.fill"
            case .config: return "gearshape.fill"
            case .test: return "network"
            case .repos: return "folder.badge.gearshape"
            case .knownHosts: return "list.bullet.rectangle.portrait"
            case .identity: return "person.2.fill"
            case .source: return "doc.text"
            case .backup: return "externaldrive.fill"
            case .guide: return "book.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(SSHTab.allCases, id: \.self) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Label(tab.rawValue, systemImage: tab.icon)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                                    )
                                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("刷新")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Permission warning bar
            if !viewModel.sshDirPermissionOK || !viewModel.badPermissionKeys.isEmpty {
                permissionWarningBar
            }

            // Message bar
            if let error = viewModel.errorMessage {
                messageBar(text: error, isError: true)
            }
            if let success = viewModel.successMessage {
                messageBar(text: success, isError: false)
            }

            // Content
            Group {
                switch selectedTab {
                case .keys:
                    KeyListView(viewModel: viewModel)
                case .config:
                    ConfigListView(viewModel: viewModel)
                case .test:
                    ConnectionTestView(viewModel: viewModel)
                case .repos:
                    RepoScanView(viewModel: viewModel)
                case .knownHosts:
                    KnownHostsView(viewModel: viewModel)
                case .identity:
                    GitIdentityView(viewModel: viewModel)
                case .source:
                    ConfigSourceView(viewModel: viewModel)
                case .backup:
                    BackupView(viewModel: viewModel)
                case .guide:
                    SSHGuideView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Status bar
            statusBar
        }
    }

    // MARK: - Sub-views

    private var permissionWarningBar: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("检测到文件权限异常")
                .font(.system(size: 12))
            Spacer()
            Button("一键修复") {
                Task { await viewModel.fixAllPermissions() }
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }

    private func messageBar(text: String, isError: Bool) -> some View {
        HStack {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(text)
                .font(.system(size: 12))
            Spacer()
            Button {
                viewModel.clearMessages()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
    }

    private var statusBar: some View {
        HStack {
            if viewModel.sshDirPermissionOK {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 10))
                Text("~/.ssh/ 权限正常")
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 10))
                Text("~/.ssh/ 权限异常")
            }
            Text("·")
            Text("\(viewModel.keyCount) 把密钥")
            Text("·")
            Text("\(viewModel.configCount) 个 Host 配置")
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
