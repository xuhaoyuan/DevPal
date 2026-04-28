import SwiftUI

/// Main SSH feature view with sidebar navigation
struct SSHMainView: View {
    @ObservedObject var viewModel: SSHViewModel
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

        var subtitle: String {
            switch self {
            case .keys: return "查看/生成 SSH 密钥"
            case .config: return "编辑 Host 配置项"
            case .test: return "测试 SSH 连接"
            case .repos: return "扫描 Git 仓库"
            case .knownHosts: return "管理已知主机"
            case .identity: return "Git includeIf 身份"
            case .source: return "直接编辑 config"
            case .backup: return "备份与恢复"
            case .guide: return "SSH 使用指南"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
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

            PersistentSplitView(id: "ssh", minWidth: 120, maxWidth: 220, defaultWidth: 150) {
                // Sidebar
                VStack(spacing: 2) {
                    ForEach(SSHTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tab.rawValue)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(tab.subtitle)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                            .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Refresh button at bottom
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("刷新")
                                .font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            } content: {
                // Content
                VStack(spacing: 0) {
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
