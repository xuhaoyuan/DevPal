import SwiftUI

struct BackupView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var backups: [(path: String, date: Date)] = []
    @State private var isCreatingBackup = false
    @State private var selectedBackup: String?
    @State private var backupContent: String?
    @State private var showRestoreConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("备份与恢复")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    Task { await createFullBackup() }
                } label: {
                    if isCreatingBackup {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("完整备份到桌面", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCreatingBackup)
            }
            .padding(12)

            Divider()

            HStack(spacing: 0) {
                // Left: Backup list
                VStack(alignment: .leading, spacing: 0) {
                    Text("自动备份快照")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(12)

                    if backups.isEmpty {
                        Spacer()
                        Text("暂无自动备份")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        List(backups, id: \.path, selection: $selectedBackup) { backup in
                            VStack(alignment: .leading, spacing: 2) {
                                Text((backup.path as NSString).lastPathComponent)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1)
                                Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .tag(backup.path)
                        }
                        .listStyle(.sidebar)
                    }
                }
                .frame(width: 280)

                Divider()

                // Right: Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("备份内容预览")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    if let content = backupContent {
                        ScrollView {
                            Text(content)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))

                        Button("恢复此备份") { showRestoreConfirm = true }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Spacer()
                        Text("选择一个备份查看内容")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { loadBackups() }
        .onChange(of: selectedBackup) {
            if let path = selectedBackup {
                backupContent = try? BackupManager.shared.readBackup(at: path)
            } else {
                backupContent = nil
            }
        }
        .alert("确认恢复", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) { }
            Button("恢复", role: .destructive) {
                if let path = selectedBackup {
                    do {
                        try BackupManager.shared.restoreConfigBackup(at: path)
                        Task { await viewModel.refresh() }
                        viewModel.successMessage = "配置已恢复"
                    } catch {
                        viewModel.errorMessage = "恢复失败: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("将用备份内容覆盖当前 ~/.ssh/config，当前配置会自动备份")
        }
    }

    private func loadBackups() {
        backups = (try? BackupManager.shared.listConfigBackups()) ?? []
    }

    private func createFullBackup() async {
        isCreatingBackup = true
        defer { isCreatingBackup = false }
        do {
            let path = try await BackupManager.shared.createFullBackup()
            viewModel.successMessage = "已备份到: \(path)"
        } catch {
            viewModel.errorMessage = "备份失败: \(error.localizedDescription)"
        }
    }
}
