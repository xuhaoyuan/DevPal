import SwiftUI

struct KeyListView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var searchText = ""
    @State private var showGenerateSheet = false
    @State private var selectedKey: SSHKey?
    @State private var showDeleteConfirm = false
    @State private var keyToDelete: SSHKey?
    @State private var cleanupConfigOnDelete = false

    var filteredKeys: [SSHKey] {
        if searchText.isEmpty { return viewModel.keys }
        let query = searchText.lowercased()
        return viewModel.keys.filter {
            $0.name.lowercased().contains(query) ||
            $0.comment.lowercased().contains(query) ||
            $0.type.rawValue.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索密钥...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .frame(maxWidth: 250)

                Spacer()

                Button {
                    showGenerateSheet = true
                } label: {
                    Label("生成新密钥", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            // Key list
            if viewModel.isLoading {
                Spacer()
                ProgressView("扫描密钥中...")
                Spacer()
            } else if filteredKeys.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "key")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "未找到 SSH 密钥" : "无搜索结果")
                        .foregroundColor(.secondary)
                    if searchText.isEmpty {
                        Button("生成第一把密钥") { showGenerateSheet = true }
                            .buttonStyle(.bordered)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredKeys) { key in
                            KeyRowView(key: key, onCopyPublicKey: { copyPublicKey(key) })
                                .contentShape(Rectangle())
                                .onTapGesture { selectedKey = key }
                                .contextMenu {
                                    Button("复制公钥") { copyPublicKey(key) }
                                    Button("查看详情") { selectedKey = key }
                                    Divider()
                                    Button("删除", role: .destructive) {
                                        keyToDelete = key
                                        showDeleteConfirm = true
                                    }
                                }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .sheet(isPresented: $showGenerateSheet) {
            KeyGenerateView(viewModel: viewModel)
        }
        .sheet(item: $selectedKey) { key in
            KeyDetailView(key: key, viewModel: viewModel)
        }
        .alert("确认删除密钥", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let key = keyToDelete {
                    Task { await viewModel.deleteKey(key, cleanupConfig: cleanupConfigOnDelete) }
                }
            }
        } message: {
            if let key = keyToDelete {
                VStack {
                    Text("将删除: \(key.name), \(key.name).pub")
                    if !key.referencedByHosts.isEmpty {
                        Text("⚠️ 被以下 Host 引用: \(key.referencedByHosts.joined(separator: ", "))")
                    }
                }
            }
        }
    }

    private func copyPublicKey(_ key: SSHKey) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key.publicKeyContent, forType: .string)
        viewModel.successMessage = "公钥已复制到剪贴板"
    }
}

// MARK: - Key Row

struct KeyRowView: View {
    let key: SSHKey
    let onCopyPublicKey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(key.name)
                    .font(.system(size: 14, weight: .medium))
                typeLabel
                if !key.isPermissionCorrect {
                    Label("权限异常", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                Spacer()
                Button("复制公钥") { onCopyPublicKey() }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            HStack(spacing: 12) {
                Label(key.type.rawValue + (key.bits != nil ? " · \(key.bits!)" : ""),
                      systemImage: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if !key.comment.isEmpty {
                    Text(key.comment)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 12) {
                Text("指纹: \(key.displayFingerprint)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                // Referenced hosts
                if key.referencedByHosts.isEmpty {
                    Text("未使用")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15)))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(key.referencedByHosts, id: \.self) { host in
                        Text(host)
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var typeLabel: some View {
        Text(key.type.rawValue)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(key.type == .ed25519 ? Color.green.opacity(0.15) :
                          key.type == .rsa ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
            )
            .foregroundColor(key.type == .ed25519 ? .green : key.type == .rsa ? .blue : .secondary)
    }
}
