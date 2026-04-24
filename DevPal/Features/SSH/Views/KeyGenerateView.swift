import SwiftUI

struct KeyGenerateView: View {
    @ObservedObject var viewModel: SSHViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var keyType: SSHKeyType = .ed25519
    @State private var keyName: String = "id_ed25519"
    @State private var comment: String = ""
    @State private var passphrase: String = ""
    @State private var showPassphrase = false
    @State private var rsaBits: Int = 4096
    @State private var isGenerating = false
    @State private var generatedKey: SSHKey?
    @State private var nameConflict = false

    var commandPreview: String {
        var cmd = "ssh-keygen -t \(keyType.sshKeygenType)"
        if keyType == .rsa { cmd += " -b \(rsaBits)" }
        if !comment.isEmpty { cmd += " -C \"\(comment)\"" }
        cmd += " -f ~/.ssh/\(keyName)"
        return cmd
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("生成新密钥")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if let key = generatedKey {
                // Success view
                successView(key: key)
            } else {
                // Form
                formView
            }
        }
        .frame(width: 500, height: 520)
        .onChange(of: keyName) {
            nameConflict = SSHKeyManager.shared.keyExists(name: keyName)
        }
        .onChange(of: keyType) {
            if keyType == .ed25519 { keyName = "id_ed25519" }
            else if keyType == .rsa { keyName = "id_rsa" }
            else { keyName = "id_\(keyType.sshKeygenType)" }
        }
    }

    // MARK: - Form

    private var formView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Key Type
                    VStack(alignment: .leading, spacing: 4) {
                        Text("密钥类型").font(.system(size: 12, weight: .medium))
                        Picker("", selection: $keyType) {
                            ForEach([SSHKeyType.ed25519, .rsa], id: \.self) { type in
                                HStack {
                                    Text(type.rawValue)
                                    if type == .ed25519 {
                                        Text("推荐").foregroundColor(.green).font(.system(size: 10))
                                    }
                                }.tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // RSA Bits
                    if keyType == .rsa {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RSA 位数").font(.system(size: 12, weight: .medium))
                            Picker("", selection: $rsaBits) {
                                Text("2048").tag(2048)
                                Text("3072").tag(3072)
                                Text("4096 (推荐)").tag(4096)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Key Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("密钥名称").font(.system(size: 12, weight: .medium))
                        TextField("id_ed25519", text: $keyName)
                            .textFieldStyle(.roundedBorder)
                        if nameConflict {
                            Label("文件名已存在，请更换", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                    }

                    // Comment
                    VStack(alignment: .leading, spacing: 4) {
                        Text("备注 / 邮箱").font(.system(size: 12, weight: .medium))
                        TextField("your@email.com", text: $comment)
                            .textFieldStyle(.roundedBorder)
                        Text("写入公钥末尾，方便识别用途")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // Passphrase
                    VStack(alignment: .leading, spacing: 4) {
                        Text("密码短语（可选）").font(.system(size: 12, weight: .medium))
                        HStack {
                            if showPassphrase {
                                TextField("留空 = 无密码", text: $passphrase)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("留空 = 无密码", text: $passphrase)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button {
                                showPassphrase.toggle()
                            } label: {
                                Image(systemName: showPassphrase ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Command Preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("即将执行的命令").font(.system(size: 12, weight: .medium))
                        Text(commandPreview)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task { await generate() }
                } label: {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("生成")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyName.isEmpty || nameConflict || isGenerating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    // MARK: - Success

    private func successView(key: SSHKey) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("密钥生成成功！")
                .font(.title2)

            VStack(alignment: .leading, spacing: 8) {
                Text("公钥内容：")
                    .font(.system(size: 12, weight: .medium))
                ScrollView {
                    Text(key.publicKeyContent)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 80)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
            .padding(.horizontal)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key.publicKeyContent, forType: .string)
                viewModel.successMessage = "公钥已复制"
            } label: {
                Label("一键复制公钥", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("请将公钥添加到 GitHub / GitLab / Codeup 等平台")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom)
        }
    }

    // MARK: - Actions

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        let params = SSHKeyManager.KeyGenerationParams(
            type: keyType,
            name: keyName,
            comment: comment,
            passphrase: passphrase,
            bits: rsaBits
        )
        generatedKey = await viewModel.generateKey(params: params)
    }
}
