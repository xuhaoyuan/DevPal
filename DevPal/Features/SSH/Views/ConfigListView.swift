import SwiftUI

struct ConfigListView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var showAddSheet = false
    @State private var editingConfig: SSHHostConfig?
    @State private var configToDelete: SSHHostConfig?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Host 配置")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
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
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ConfigEditView(viewModel: viewModel, config: nil)
        }
        .sheet(item: $editingConfig) { config in
            ConfigEditView(viewModel: viewModel, config: config)
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
}

// MARK: - Config Card

struct ConfigCardView: View {
    let config: SSHHostConfig
    let testResult: ConnectionTestResult?

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
