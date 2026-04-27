import SwiftUI

/// Manage ~/.ssh/known_hosts file
struct KnownHostsView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var entries: [KnownHostsManager.KnownHostEntry] = []
    @State private var duplicates: [String: [KnownHostsManager.KnownHostEntry]] = [:]
    @State private var searchText = ""
    @State private var selectedEntries: Set<Int> = []  // line numbers
    @State private var showDeleteConfirm = false

    private let manager = KnownHostsManager.shared

    var filteredEntries: [KnownHostsManager.KnownHostEntry] {
        if searchText.isEmpty { return entries }
        let q = searchText.lowercased()
        return entries.filter {
            $0.host.lowercased().contains(q) || $0.keyType.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("known_hosts 管理")
                    .font(.system(size: 14, weight: .medium))

                Spacer()

                if !selectedEntries.isEmpty {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除选中 (\(selectedEntries.count))", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.red)
                }

                Button {
                    loadEntries()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            // Duplicates warning
            if !duplicates.isEmpty {
                duplicateWarning
            }

            if entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("known_hosts 为空")
                        .foregroundColor(.secondary)
                    Text("首次连接 SSH 服务器时会自动添加记录")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // Search + stats
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索主机...", text: $searchText)
                        .textFieldStyle(.plain)
                    Text("\(entries.count) 条记录")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Entry list
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredEntries) { entry in
                            entryRow(entry)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear { loadEntries() }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除 \(selectedEntries.count) 条", role: .destructive) {
                deleteSelected()
            }
        } message: {
            Text("将从 known_hosts 中删除选中的 \(selectedEntries.count) 条记录。\n下次连接时会重新验证服务器指纹。")
        }
    }

    private var duplicateWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("检测到重复主机记录")
                    .font(.system(size: 11, weight: .medium))
                Text("以下主机有多条记录: \(duplicates.keys.joined(separator: ", "))。可能是服务器更换过密钥。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("选中重复项") {
                selectDuplicates()
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private func entryRow(_ entry: KnownHostsManager.KnownHostEntry) -> some View {
        let isSelected = selectedEntries.contains(entry.lineNumber)
        let isDuplicate = duplicates.keys.contains(where: { entry.host.contains($0) })

        return HStack(spacing: 8) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .font(.system(size: 13))
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelected {
                        selectedEntries.remove(entry.lineNumber)
                    } else {
                        selectedEntries.insert(entry.lineNumber)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.host)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    if isDuplicate {
                        Text("重复")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.15)))
                            .foregroundColor(.orange)
                    }
                }
                HStack(spacing: 8) {
                    Text(entry.keyType)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(entry.keyFingerprint)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("L\(entry.lineNumber)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        )
    }

    // MARK: - Actions

    private func loadEntries() {
        entries = manager.loadEntries()
        duplicates = manager.findDuplicates()
        selectedEntries = []
    }

    private func deleteSelected() {
        do {
            try manager.removeEntries(lineNumbers: selectedEntries)
            viewModel.successMessage = "已删除 \(selectedEntries.count) 条 known_hosts 记录"
            loadEntries()
        } catch {
            viewModel.errorMessage = "删除失败: \(error.localizedDescription)"
        }
    }

    private func selectDuplicates() {
        for (_, entries) in duplicates {
            // Select all but the newest (last) entry for each duplicate group
            for entry in entries.dropLast() {
                selectedEntries.insert(entry.lineNumber)
            }
        }
    }
}
