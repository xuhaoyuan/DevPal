import SwiftUI
import AppKit

struct BackupView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var backups: [(path: String, date: Date)] = []
    @State private var isCreatingBackup = false
    @State private var selectedBackup: String?
    @State private var backupContent: String?
    @State private var isLoadingContent = false
    @State private var showRestoreConfirm = false
    @State private var showDeleteConfirm = false
    @State private var backupToDelete: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("备份与恢复")
                    .font(.system(size: 14, weight: .medium))
                Spacer()

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.ssh/.backup"))
                } label: {
                    Label("打开备份目录", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

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

            PersistentSplitView(id: "backup", minWidth: 200, maxWidth: 400, defaultWidth: 280) {
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
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((backup.path as NSString).lastPathComponent)
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineLimit(1)
                                    Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    backupToDelete = backup.path
                                    showDeleteConfirm = true
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("删除此备份")
                            }
                            .tag(backup.path)
                        }
                        .listStyle(.sidebar)
                    }
                }
                .frame(maxHeight: .infinity)
            } content: {
                // Right: Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("备份内容预览")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    if isLoadingContent {
                        Spacer()
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if let content = backupContent {
                        ReadOnlyTextView(text: content, font: .monospacedSystemFont(ofSize: 11, weight: .regular))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

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
            loadSelectedBackupContent()
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
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { backupToDelete = nil }
            Button("删除", role: .destructive) {
                if let path = backupToDelete {
                    deleteBackup(at: path)
                    backupToDelete = nil
                }
            }
        } message: {
            if let path = backupToDelete {
                Text("将永久删除备份文件 \((path as NSString).lastPathComponent)")
            }
        }
    }

    private func loadBackups() {
        backups = (try? BackupManager.shared.listConfigBackups()) ?? []
    }

    private func loadSelectedBackupContent() {
        guard let path = selectedBackup else {
            backupContent = nil
            return
        }
        isLoadingContent = true
        backupContent = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let content = try? BackupManager.shared.readBackup(at: path)
            DispatchQueue.main.async {
                backupContent = content
                isLoadingContent = false
            }
        }
    }

    private func deleteBackup(at path: String) {
        do {
            try FileManager.default.removeItem(atPath: path)
            if selectedBackup == path {
                selectedBackup = nil
                backupContent = nil
            }
            loadBackups()
        } catch {
            viewModel.errorMessage = "删除失败: \(error.localizedDescription)"
        }
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
