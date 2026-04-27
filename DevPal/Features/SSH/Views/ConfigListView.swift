import SwiftUI

struct ConfigListView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var showAddSheet = false
    @State private var showWizard = false
    @State private var editingConfig: SSHHostConfig?
    @State private var configToDelete: SSHHostConfig?
    @State private var diagnosticConfig: SSHHostConfig?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Host 配置")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    showWizard = true
                } label: {
                    Label("多账号向导", systemImage: "person.2.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("同一平台多账号 SSH 配置向导")

                Button {
                    showAddSheet = true
                } label: {
                    Label("新增 Host", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            // Multi-account conflict warning
            if !viewModel.configsMissingIdentityAgent().isEmpty {
                multiAccountWarning
            }

            if viewModel.configs.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无 Host 配置")
                        .foregroundColor(.secondary)
                    if FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.ssh/config") {
                        Text("~/.ssh/config 为空或无法解析")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("~/.ssh/config 文件不存在")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Button("新增第一个 Host") { showAddSheet = true }
                        .buttonStyle(.bordered)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.configs) { config in
                            ConfigCardView(
                                config: config,
                                testResult: viewModel.testResults[config.host]
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { editingConfig = config }
                            .contextMenu {
                                Button("编辑") { editingConfig = config }
                                Button("测试连接") {
                                    Task { await viewModel.testConnection(for: config) }
                                }
                                if !config.isGlobal {
                                    Button("诊断连接") { diagnosticConfig = config }
                                }
                                Divider()
                                Button("删除", role: .destructive) {
                                    configToDelete = config
                                    showDeleteConfirm = true
                                }
                            }
                        }
                    }
                    .padding(12)
                }

                // URL Rewrite Rules Section
                if !viewModel.urlRewriteRules.isEmpty {
                    urlRewriteSection
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ConfigEditView(viewModel: viewModel, config: nil)
        }
        .sheet(isPresented: $showWizard) {
            MultiAccountWizardView(viewModel: viewModel)
        }
        .sheet(item: $editingConfig) { config in
            ConfigEditView(viewModel: viewModel, config: config)
        }
        .sheet(item: $diagnosticConfig) { config in
            DiagnosticView(viewModel: viewModel, config: config)
        }
        .alert("确认删除 Host 配置", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let config = configToDelete {
                    Task { await viewModel.removeConfig(config) }
                }
            }
        } message: {
            if let config = configToDelete {
                Text("将删除 Host \"\(config.host)\" 配置\n关联的密钥文件不会被删除")
            }
        }
    }

    // MARK: - Multi-Account Warning

    private var multiAccountWarning: some View {
        let badConfigs = viewModel.configsMissingIdentityAgent()
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("检测到多账号配置缺少 IdentityAgent none")
                    .font(.system(size: 11, weight: .medium))
                Text("涉及: \(badConfigs.map(\.host).joined(separator: ", "))。SSH Agent 会缓存所有用过的密钥并自动尝试，多账号时可能提供错误账号的密钥导致认证失败。设为 none 可强制只用 IdentityFile 指定的密钥。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("使用向导修复") { showWizard = true }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - URL Rewrite Section

    private var urlRewriteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.horizontal, 12)

            HStack {
                Label("Git URL 重写规则", systemImage: "arrow.triangle.swap")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("~/.gitconfig [url] insteadOf")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)

            ForEach(viewModel.urlRewriteRules) { rule in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(rule.from)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.red.opacity(0.7))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(rule.to)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await viewModel.removeURLRewriteRule(rule) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("删除此重写规则")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Config Card

struct ConfigCardView: View {
    let config: SSHHostConfig
    let testResult: ConnectionTestResult?

    @State private var showCopiedHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Host name
                Text(config.isGlobal ? "全局默认配置" : config.host)
                    .font(.system(size: 14, weight: .medium))
                if config.isGlobal {
                    Text("Host *")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.purple.opacity(0.12)))
                        .foregroundColor(.purple)
                }

                Spacer()

                // Quick copy clone URL
                if !config.isGlobal {
                    Button {
                        let url = "git@\(config.host):"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        showCopiedHint = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedHint = false
                        }
                    } label: {
                        if showCopiedHint {
                            Label("已复制", systemImage: "checkmark")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("复制 git@\(config.host): 前缀到剪贴板")
                }

                // Test result indicator
                if let result = testResult {
                    testStatusView(result.status)
                }
            }

            HStack(spacing: 16) {
                if !config.hostName.isEmpty {
                    Label(config.hostName, systemImage: "globe")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if !config.user.isEmpty {
                    Label(config.user, systemImage: "person")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if let port = config.displayPort {
                    Label(port, systemImage: "number")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            if !config.identityFile.isEmpty {
                HStack {
                    Label(config.identityFileName, systemImage: "key")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    // Check if key file exists
                    let fullPath = config.identityFile
                        .replacingOccurrences(of: "~", with: NSHomeDirectory())
                    if !FileManager.default.fileExists(atPath: fullPath) {
                        Label("密钥文件不存在", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private func testStatusView(_ status: ConnectionStatus) -> some View {
        switch status {
        case .untested:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.mini)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))
        case .timeout:
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(.orange)
                .font(.system(size: 14))
        }
    }
}
