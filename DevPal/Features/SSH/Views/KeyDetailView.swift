import SwiftUI

struct KeyDetailView: View {
    let key: SSHKey
    @ObservedObject var viewModel: SSHViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showRenameField = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(key.name)
                    .font(.headline)
                typeLabel
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Public Key
                    section(title: "公钥") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(key.publicKeyContent)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(4)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(key.publicKeyContent, forType: .string)
                            } label: {
                                Label("复制公钥", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    // Fingerprints
                    section(title: "指纹") {
                        fingerprintRow(label: "MD5", value: key.fingerprintMD5)
                        fingerprintRow(label: "SHA256", value: key.fingerprintSHA256)
                    }

                    // Details
                    section(title: "详细信息") {
                        detailRow(label: "类型", value: key.type.rawValue)
                        if let bits = key.bits {
                            detailRow(label: "位数", value: "\(bits)")
                        }
                        detailRow(label: "备注", value: key.comment.isEmpty ? "-" : key.comment)
                        detailRow(label: "修改时间", value: key.modificationDate.formatted())
                    }

                    // File Info
                    section(title: "文件信息") {
                        detailRow(label: "私钥", value: key.privateKeyPath)
                        detailRow(label: "公钥", value: key.publicKeyPath)
                        HStack {
                            detailRow(label: "权限", value: key.filePermissions)
                            if !key.isPermissionCorrect {
                                Label("应为 600", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                Button("修复") {
                                    try? FilePermissions.fixPrivateKey(at: key.privateKeyPath)
                                    Task { await viewModel.refresh() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }

                    // Referenced Hosts
                    section(title: "被引用的 Host 配置") {
                        if key.referencedByHosts.isEmpty {
                            Text("未被任何 Host 引用")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(key.referencedByHosts, id: \.self) { host in
                                HStack {
                                    Image(systemName: "link")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                    Text(host)
                                        .font(.system(size: 12))
                                }
                            }
                        }
                    }

                    // Rename
                    section(title: "操作") {
                        if showRenameField {
                            HStack {
                                TextField("新名称", text: $newName)
                                    .textFieldStyle(.roundedBorder)
                                Button("确认重命名") {
                                    Task {
                                        await viewModel.renameKey(key, to: newName)
                                        dismiss()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(newName.isEmpty)
                                Button("取消") { showRenameField = false }
                                    .buttonStyle(.plain)
                            }
                        } else {
                            Button("重命名密钥") {
                                newName = key.name
                                showRenameField = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: 600)
    }

    // MARK: - Helpers

    private var typeLabel: some View {
        Text(key.type.rawValue)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
            .foregroundColor(.accentColor)
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func fingerprintRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 50, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
    }
}
