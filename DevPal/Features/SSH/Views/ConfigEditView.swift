import SwiftUI

struct ConfigEditView: View {
    @ObservedObject var viewModel: SSHViewModel
    let config: SSHHostConfig? // nil = new
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var hostName = ""
    @State private var user = "git"
    @State private var port = "22"
    @State private var identityFile = ""
    @State private var identitiesOnly = true
    @State private var preferredAuth = "publickey"

    // Advanced
    @State private var showAdvanced = false
    @State private var forwardAgent = false
    @State private var proxyCommand = ""
    @State private var proxyJump = ""
    @State private var serverAliveInterval = ""
    @State private var serverAliveCountMax = ""
    @State private var addKeysToAgent = ""
    @State private var useKeychain = false

    var isEditing: Bool { config != nil }

    var previewText: String {
        var lines = ["Host \(host)"]
        if !hostName.isEmpty { lines.append("  HostName \(hostName)") }
        if !user.isEmpty { lines.append("  User \(user)") }
        if port != "22", let p = Int(port) { lines.append("  Port \(p)") }
        if !preferredAuth.isEmpty { lines.append("  PreferredAuthentications \(preferredAuth)") }
        if !identityFile.isEmpty { lines.append("  IdentityFile \(identityFile)") }
        if identitiesOnly { lines.append("  IdentitiesOnly yes") }
        if forwardAgent { lines.append("  ForwardAgent yes") }
        if !proxyCommand.isEmpty { lines.append("  ProxyCommand \(proxyCommand)") }
        if !proxyJump.isEmpty { lines.append("  ProxyJump \(proxyJump)") }
        if let sai = Int(serverAliveInterval) { lines.append("  ServerAliveInterval \(sai)") }
        if let sacm = Int(serverAliveCountMax) { lines.append("  ServerAliveCountMax \(sacm)") }
        if !addKeysToAgent.isEmpty { lines.append("  AddKeysToAgent \(addKeysToAgent)") }
        if useKeychain { lines.append("  UseKeychain yes") }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "编辑 Host: \(config!.host)" : "新增 Host 配置")
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

            HStack(spacing: 0) {
                // Left: Form
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("基础配置").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)

                        formField("Host (别名)", text: $host, placeholder: "codeup-work", tooltip: "git remote URL 中 @ 后面的部分")
                        formField("HostName (域名)", text: $hostName, placeholder: "codeup.aliyun.com")
                        formField("User", text: $user, placeholder: "git")
                        formField("Port", text: $port, placeholder: "22")

                        // Identity file picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("IdentityFile").font(.system(size: 12, weight: .medium))
                            Picker("", selection: $identityFile) {
                                Text("不指定").tag("")
                                ForEach(viewModel.availablePrivateKeys(), id: \.path) { key in
                                    Text("\(key.name) (\(key.type.rawValue))")
                                        .tag("~/.ssh/\(key.name)")
                                }
                            }
                            .labelsHidden()
                        }

                        Toggle("IdentitiesOnly (只用指定的 key)", isOn: $identitiesOnly)
                            .font(.system(size: 12))

                        formField("PreferredAuthentications", text: $preferredAuth, placeholder: "publickey")

                        // Advanced toggle
                        Divider()
                        DisclosureGroup("高级配置", isExpanded: $showAdvanced) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("ForwardAgent", isOn: $forwardAgent)
                                    .font(.system(size: 12))
                                formField("ProxyCommand", text: $proxyCommand, placeholder: "")
                                formField("ProxyJump", text: $proxyJump, placeholder: "jump-host")
                                formField("ServerAliveInterval", text: $serverAliveInterval, placeholder: "60")
                                formField("ServerAliveCountMax", text: $serverAliveCountMax, placeholder: "3")
                                formField("AddKeysToAgent", text: $addKeysToAgent, placeholder: "yes")
                                Toggle("UseKeychain (macOS)", isOn: $useKeychain)
                                    .font(.system(size: 12))
                            }
                            .padding(.top, 8)
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right: Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("配置预览")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    ScrollView {
                        Text(previewText)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                }
                .padding()
                .frame(width: 260)
            }

            Divider()

            // Actions
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "保存修改" : "添加") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 680, height: 520)
        .onAppear { loadExisting() }
    }

    // MARK: - Helpers

    private func formField(_ label: String, text: Binding<String>, placeholder: String, tooltip: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 12, weight: .medium))
                if let tip = tooltip {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .help(tip)
                }
            }
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    private func loadExisting() {
        guard let c = config else { return }
        host = c.host
        hostName = c.hostName
        user = c.user
        port = c.port.map { "\($0)" } ?? "22"
        identityFile = c.identityFile
        identitiesOnly = c.identitiesOnly
        preferredAuth = c.preferredAuthentications ?? "publickey"
        forwardAgent = c.forwardAgent ?? false
        proxyCommand = c.proxyCommand ?? ""
        proxyJump = c.proxyJump ?? ""
        serverAliveInterval = c.serverAliveInterval.map { "\($0)" } ?? ""
        serverAliveCountMax = c.serverAliveCountMax.map { "\($0)" } ?? ""
        addKeysToAgent = c.addKeysToAgent ?? ""
        useKeychain = c.useKeychain ?? false
    }

    private func save() async {
        var newConfig = config ?? SSHHostConfig()
        newConfig.host = host
        newConfig.hostName = hostName
        newConfig.user = user
        newConfig.port = Int(port)
        newConfig.identityFile = identityFile
        newConfig.identitiesOnly = identitiesOnly
        newConfig.preferredAuthentications = preferredAuth.isEmpty ? nil : preferredAuth
        newConfig.forwardAgent = forwardAgent ? true : nil
        newConfig.proxyCommand = proxyCommand.isEmpty ? nil : proxyCommand
        newConfig.proxyJump = proxyJump.isEmpty ? nil : proxyJump
        newConfig.serverAliveInterval = Int(serverAliveInterval)
        newConfig.serverAliveCountMax = Int(serverAliveCountMax)
        newConfig.addKeysToAgent = addKeysToAgent.isEmpty ? nil : addKeysToAgent
        newConfig.useKeychain = useKeychain ? true : nil

        if isEditing {
            await viewModel.updateConfig(newConfig)
        } else {
            await viewModel.addConfig(newConfig)
        }
        dismiss()
    }
}
