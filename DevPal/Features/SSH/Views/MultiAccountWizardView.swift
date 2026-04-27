import SwiftUI

// MARK: - Platform Template

struct PlatformTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let hostName: String
    let defaultUser: String
    let testCommand: String  // e.g. "ssh -T git@<host>"

    static let presets: [PlatformTemplate] = [
        PlatformTemplate(
            id: "codeup",
            name: "阿里云 Codeup",
            icon: "building.2",
            hostName: "codeup.aliyun.com",
            defaultUser: "git",
            testCommand: "ssh -T git@<host>"
        ),
        PlatformTemplate(
            id: "github",
            name: "GitHub",
            icon: "globe.americas",
            hostName: "github.com",
            defaultUser: "git",
            testCommand: "ssh -T git@<host>"
        ),
        PlatformTemplate(
            id: "gitlab",
            name: "GitLab",
            icon: "globe.europe.africa",
            hostName: "gitlab.com",
            defaultUser: "git",
            testCommand: "ssh -T git@<host>"
        ),
        PlatformTemplate(
            id: "bitbucket",
            name: "Bitbucket",
            icon: "globe.asia.australia",
            hostName: "bitbucket.org",
            defaultUser: "git",
            testCommand: "ssh -T git@<host>"
        ),
        PlatformTemplate(
            id: "gitee",
            name: "Gitee (码云)",
            icon: "globe.central.south.asia",
            hostName: "gitee.com",
            defaultUser: "git",
            testCommand: "ssh -T git@<host>"
        ),
        PlatformTemplate(
            id: "custom",
            name: "自定义平台",
            icon: "server.rack",
            hostName: "",
            defaultUser: "git",
            testCommand: "ssh -T git@<host>"
        ),
    ]
}

// MARK: - Wizard Step

enum WizardStep: Int, CaseIterable {
    case platform = 0
    case account
    case key
    case urlRewrite
    case review

    var title: String {
        switch self {
        case .platform: return "选择平台"
        case .account: return "账号信息"
        case .key: return "密钥配置"
        case .urlRewrite: return "URL 路由"
        case .review: return "确认"
        }
    }
}

// MARK: - Multi-Account Wizard View

struct MultiAccountWizardView: View {
    @ObservedObject var viewModel: SSHViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: WizardStep = .platform
    @State private var selectedPlatform: PlatformTemplate?
    @State private var customHostName = ""
    @State private var accountLabel = ""
    @State private var user = "git"

    // Key selection
    enum KeyChoice: Hashable {
        case existing(String)  // key name
        case generate
    }
    @State private var keyChoice: KeyChoice = .generate
    @State private var newKeyName = ""
    @State private var newKeyComment = ""
    @State private var newKeyType: SSHKeyType = .ed25519

    // URL rewrite
    @State private var enableURLRewrite = true
    @State private var urlRewriteFrom = ""  // e.g. "git@codeup.aliyun.com:myorg/"
    @State private var urlRewriteScope = ""  // org/path prefix for scoped rewrite

    // Generated result
    @State private var isCreating = false
    @State private var createdConfig: SSHHostConfig?
    @State private var generatedPublicKey: String?
    @State private var errorMessage: String?

    // MARK: - Computed

    var hostAlias: String {
        guard let platform = selectedPlatform else { return "" }
        let base = platform.id == "custom" ? customHostName.replacingOccurrences(of: ".", with: "-") : platform.id
        return accountLabel.isEmpty ? base : "\(base)-\(accountLabel)"
    }

    var actualHostName: String {
        guard let platform = selectedPlatform else { return "" }
        return platform.id == "custom" ? customHostName : platform.hostName
    }

    var identityFilePath: String {
        switch keyChoice {
        case .existing(let name):
            return "~/.ssh/\(name)"
        case .generate:
            return "~/.ssh/\(newKeyName)"
        }
    }

    var conflictingConfigs: [SSHHostConfig] {
        viewModel.configs.filter { $0.hostName == actualHostName && $0.host != hostAlias }
    }

    var hostAliasConflict: Bool {
        viewModel.configs.contains { $0.host == hostAlias }
    }

    var previewConfig: SSHHostConfig {
        SSHHostConfig(
            host: hostAlias,
            hostName: actualHostName,
            user: user,
            identityFile: identityFilePath,
            identitiesOnly: true,
            identityAgent: "none",
            preferredAuthentications: "publickey"
        )
    }

    var gitRemoteExample: String {
        "git@\(hostAlias):your-org/your-repo.git"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("多账号配置向导")
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

            // Step indicator
            stepIndicator

            Divider()

            // Content
            Group {
                switch step {
                case .platform: platformStep
                case .account: accountStep
                case .key: keyStep
                case .urlRewrite: urlRewriteStep
                case .review: reviewStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Error bar
            if let err = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.system(size: 11))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }

            // Navigation buttons
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if step != .platform {
                    Button("上一步") {
                        withAnimation { step = WizardStep(rawValue: step.rawValue - 1)! }
                    }
                }

                if step == .review {
                    Button("完成配置") {
                        Task { await createConfiguration() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreating || hostAlias.isEmpty || actualHostName.isEmpty)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("下一步") {
                        withAnimation { step = WizardStep(rawValue: step.rawValue + 1)! }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 520)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(WizardStep.allCases, id: \.self) { s in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 24, height: 24)
                        if s.rawValue < step.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(s.rawValue + 1)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(s.rawValue <= step.rawValue ? .white : .secondary)
                        }
                    }
                    Text(s.title)
                        .font(.system(size: 11, weight: s == step ? .semibold : .regular))
                        .foregroundColor(s == step ? .primary : .secondary)
                }
                if s != WizardStep.allCases.last {
                    Rectangle()
                        .fill(s.rawValue < step.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Step 1: Platform

    private var platformStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("选择你要配置多账号的 Git 托管平台：")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(PlatformTemplate.presets) { platform in
                        platformCard(platform)
                    }
                }
            }
            .padding(20)
        }
    }

    private func platformCard(_ platform: PlatformTemplate) -> some View {
        let isSelected = selectedPlatform?.id == platform.id
        return VStack(spacing: 8) {
            Image(systemName: platform.icon)
                .font(.system(size: 24))
                .foregroundColor(isSelected ? .accentColor : .secondary)
            Text(platform.name)
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
            if !platform.hostName.isEmpty {
                Text(platform.hostName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPlatform = platform
            // Auto-fill key name based on platform
            if platform.id != "custom" {
                newKeyName = "\(platform.id)_ed25519"
            }
        }
    }

    // MARK: - Step 2: Account

    private var accountStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Explanation
                VStack(alignment: .leading, spacing: 8) {
                    Label("为什么需要别名？", systemImage: "info.circle")
                        .font(.system(size: 13, weight: .medium))
                    Text("同一台电脑上多个账号访问相同平台时，SSH 无法自动区分使用哪把密钥。通过 Host 别名，你可以让不同账号使用不同的密钥，互不干扰。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))

                VStack(alignment: .leading, spacing: 4) {
                    Text("账号标识").font(.system(size: 12, weight: .medium))
                    TextField("例如: work、personal、company-A", text: $accountLabel)
                        .textFieldStyle(.roundedBorder)
                    Text("用于区分不同账号，将生成 Host 别名: \(hostAlias.isEmpty ? "..." : hostAlias)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if selectedPlatform?.id == "custom" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("平台域名").font(.system(size: 12, weight: .medium))
                        TextField("例如: git.mycompany.com", text: $customHostName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("用户名").font(.system(size: 12, weight: .medium))
                    TextField("git", text: $user)
                        .textFieldStyle(.roundedBorder)
                    Text("Git 平台通常使用 git 作为用户名")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Conflict warnings
                if hostAliasConflict {
                    Label("Host 别名 \"\(hostAlias)\" 已存在，请更换标识", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }

                if !conflictingConfigs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("检测到同平台已有配置：", systemImage: "info.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                        ForEach(conflictingConfigs) { config in
                            HStack(spacing: 6) {
                                Text("• \(config.host)")
                                    .font(.system(size: 11, design: .monospaced))
                                Text("→")
                                    .foregroundColor(.secondary)
                                Text(config.identityFileName)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("新配置将使用独立的密钥，不影响已有配置。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))
                }
            }
            .padding(20)
        }
    }

    // MARK: - Step 3: Key

    private var keyStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("选择此账号使用的密钥：")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                // Option: use existing key
                VStack(alignment: .leading, spacing: 8) {
                    Text("使用已有密钥").font(.system(size: 12, weight: .medium))
                    ForEach(viewModel.keys, id: \.id) { key in
                        let isSelected = keyChoice == .existing(key.name)
                        HStack {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key.name)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                HStack(spacing: 8) {
                                    Text(key.type.rawValue)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    if !key.comment.isEmpty {
                                        Text(key.comment)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    if !key.referencedByHosts.isEmpty {
                                        Text("已用于: \(key.referencedByHosts.joined(separator: ", "))")
                                            .font(.system(size: 10))
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            keyChoice = .existing(key.name)
                        }
                    }

                    if viewModel.keys.isEmpty {
                        Text("暂无已有密钥")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(8)
                    }
                }

                Divider()

                // Option: generate new key
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: keyChoice == .generate ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(keyChoice == .generate ? .accentColor : .secondary)
                        Text("生成新密钥").font(.system(size: 12, weight: .medium))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { keyChoice = .generate }

                    if keyChoice == .generate {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("密钥类型").font(.system(size: 11, weight: .medium))
                                Picker("", selection: $newKeyType) {
                                    Text("ED25519 (推荐)").tag(SSHKeyType.ed25519)
                                    Text("RSA").tag(SSHKeyType.rsa)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 240)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("密钥名称").font(.system(size: 11, weight: .medium))
                                TextField("codeup_work_ed25519", text: $newKeyName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                if SSHKeyManager.shared.keyExists(name: newKeyName) {
                                    Label("名称已存在", systemImage: "exclamationmark.triangle")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("备注 / 邮箱").font(.system(size: 11, weight: .medium))
                                TextField("your@email.com", text: $newKeyComment)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(.leading, 28)
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: accountLabel) { updateKeyName() }
        .onChange(of: selectedPlatform) { updateKeyName() }
        .onChange(of: newKeyType) { updateKeyName() }
    }

    private func updateKeyName() {
        guard keyChoice == .generate else { return }
        let platform = selectedPlatform?.id ?? "key"
        let label = accountLabel.isEmpty ? "" : "_\(accountLabel)"
        let typeSuffix = newKeyType == .ed25519 ? "_ed25519" : "_rsa"
        newKeyName = "\(platform)\(label)\(typeSuffix)"
    }

    // MARK: - Step 4: URL Rewrite

    private var urlRewriteStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("什么是 URL 自动路由？", systemImage: "info.circle")
                        .font(.system(size: 13, weight: .medium))
                    Text("通过 git 的 URL 重写规则（insteadOf），可以让特定组织/路径下的仓库自动使用对应的 Host 别名，无需手动修改每个仓库的 remote URL。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))

                Toggle(isOn: $enableURLRewrite) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用 URL 自动路由")
                            .font(.system(size: 12, weight: .medium))
                        Text("在 ~/.gitconfig 中添加 insteadOf 规则")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                if enableURLRewrite {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("组织/路径前缀（可选）").font(.system(size: 12, weight: .medium))
                            TextField("例如: my-company/", text: $urlRewriteScope)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            Text("留空 = 该平台所有仓库都走此账号；填写 = 只有匹配前缀的仓库走此账号")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Preview
                        VStack(alignment: .leading, spacing: 6) {
                            Text("规则预览：").font(.system(size: 12, weight: .medium))

                            let fromURL = "git@\(actualHostName):\(urlRewriteScope)"
                            let toURL = "git@\(hostAlias):\(urlRewriteScope)"

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("匹配:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                    Text(fromURL)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                HStack(spacing: 4) {
                                    Text("替换:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                    Text(toURL)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))

                            Text("效果：git clone/push/pull 时，git 会自动将匹配的 URL 替换为别名，从而使用正确的密钥。")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Existing rules warning
                        let existingRules = viewModel.urlRewriteRules.filter {
                            $0.from.contains(actualHostName)
                        }
                        if !existingRules.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("已有相关 URL 重写规则：", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.orange)
                                ForEach(existingRules) { rule in
                                    Text("\(rule.from) → \(rule.to)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.06)))
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            // Pre-fill the rewrite scope
            if urlRewriteFrom.isEmpty {
                urlRewriteFrom = "git@\(actualHostName):"
            }
        }
    }

    // MARK: - Step 5: Review

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("请确认以下配置：")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                // Config preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("将添加到 ~/.ssh/config：")
                        .font(.system(size: 12, weight: .medium))
                    Text(previewConfig.toConfigText())
                        .font(.system(size: 12, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        .textSelection(.enabled)
                }

                Divider()

                // Key info
                VStack(alignment: .leading, spacing: 6) {
                    Text("密钥：").font(.system(size: 12, weight: .medium))
                    switch keyChoice {
                    case .existing(let name):
                        Label("使用已有密钥: \(name)", systemImage: "key.fill")
                            .font(.system(size: 12))
                    case .generate:
                        Label("将生成新密钥: \(newKeyName)", systemImage: "plus.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                }

                Divider()

                // URL rewrite info
                if enableURLRewrite {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("URL 自动路由：").font(.system(size: 12, weight: .medium))
                        let fromURL = "git@\(actualHostName):\(urlRewriteScope)"
                        let toURL = "git@\(hostAlias):\(urlRewriteScope)"
                        Label("将在 ~/.gitconfig 添加规则", systemImage: "arrow.triangle.swap")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("\(fromURL) → \(toURL)")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                            .textSelection(.enabled)
                        Text("添加后，匹配的 git 操作会自动使用此账号的密钥，无需手动改 remote URL")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Show manual usage hint only if URL rewrite is disabled
                    usageHintSection
                }

                Divider()

                // Test command hint
                VStack(alignment: .leading, spacing: 4) {
                    Text("验证连接：").font(.system(size: 12, weight: .medium))
                    Text("ssh -T git@\(hostAlias)")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                }
            }
            .padding(20)
        }
    }

    private var usageHintSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("配置完成后如何使用", systemImage: "lightbulb.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("克隆仓库时，将 URL 中的域名替换为 Host 别名：")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("原始：").font(.system(size: 10)).foregroundColor(.secondary)
                        Text("git@\(actualHostName):org/repo.git")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("替换为：").font(.system(size: 10)).foregroundColor(.secondary)
                        Text("git@\(hostAlias):org/repo.git")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))

                Text("已有仓库可使用以下命令切换：")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("git remote set-url origin git@\(hostAlias):org/repo.git")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.06)))
    }

    // MARK: - Validation

    private var canProceed: Bool {
        switch step {
        case .platform:
            return selectedPlatform != nil
        case .account:
            let hasHostName = selectedPlatform?.id != "custom" || !customHostName.isEmpty
            return !accountLabel.isEmpty && hasHostName && !hostAliasConflict
        case .key:
            switch keyChoice {
            case .existing(let name):
                return !name.isEmpty
            case .generate:
                return !newKeyName.isEmpty && !SSHKeyManager.shared.keyExists(name: newKeyName)
            }
        case .urlRewrite:
            return true
        case .review:
            return true
        }
    }

    // MARK: - Create Configuration

    private func createConfiguration() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        // Step 1: Generate key if needed
        if case .generate = keyChoice {
            let params = SSHKeyManager.KeyGenerationParams(
                type: newKeyType,
                name: newKeyName,
                comment: newKeyComment,
                passphrase: "",
                bits: newKeyType == .rsa ? 4096 : 256
            )
            guard let key = await viewModel.generateKey(params: params) else {
                errorMessage = "密钥生成失败"
                return
            }
            generatedPublicKey = key.publicKeyContent
        }

        // Step 2: Create config entry
        let config = previewConfig
        await viewModel.addConfig(config)
        createdConfig = config

        // Step 3: Add URL rewrite rule if enabled
        if enableURLRewrite {
            let fromURL = "git@\(actualHostName):\(urlRewriteScope)"
            let toURL = "git@\(hostAlias):\(urlRewriteScope)"
            await viewModel.addURLRewriteRule(from: fromURL, to: toURL)
        }

        dismiss()
    }
}
