import SwiftUI

/// Built-in SSH documentation and field reference
struct SSHGuideView: View {
    @State private var selectedSection: GuideSection = .overview
    @State private var searchText = ""

    enum GuideSection: String, CaseIterable, Identifiable {
        case overview = "SSH 概览"
        case configFields = "Config 字段"
        case keyTypes = "密钥类型"
        case multiAccount = "多账号配置"
        case knownHosts = "known_hosts"
        case gitIntegration = "Git 集成"
        case troubleshooting = "常见问题"
        case permissions = "文件权限"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "book.fill"
            case .configFields: return "list.bullet.rectangle"
            case .keyTypes: return "key.fill"
            case .multiAccount: return "person.2.fill"
            case .knownHosts: return "shield.lefthalf.filled"
            case .gitIntegration: return "arrow.triangle.branch"
            case .troubleshooting: return "wrench.and.screwdriver.fill"
            case .permissions: return "lock.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    TextField("搜索...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .padding(8)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(filteredSections) { section in
                            Button {
                                selectedSection = section
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: section.icon)
                                        .font(.system(size: 11))
                                        .frame(width: 16)
                                    Text(section.rawValue)
                                        .font(.system(size: 12))
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(selectedSection == section ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                                .foregroundColor(selectedSection == section ? .accentColor : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: 160)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionContent(selectedSection)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var filteredSections: [GuideSection] {
        if searchText.isEmpty { return GuideSection.allCases }
        let q = searchText.lowercased()
        return GuideSection.allCases.filter { section in
            section.rawValue.lowercased().contains(q) ||
            sectionSearchableText(section).lowercased().contains(q)
        }
    }

    // MARK: - Content Router

    @ViewBuilder
    private func sectionContent(_ section: GuideSection) -> some View {
        switch section {
        case .overview: overviewSection
        case .configFields: configFieldsSection
        case .keyTypes: keyTypesSection
        case .multiAccount: multiAccountSection
        case .knownHosts: knownHostsSection
        case .gitIntegration: gitIntegrationSection
        case .troubleshooting: troubleshootingSection
        case .permissions: permissionsSection
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("SSH 概览")

            docParagraph("""
            SSH (Secure Shell) 是一种加密网络协议，用于在不安全的网络上安全地远程操作。\
            在开发中，SSH 最常见的用途是通过 Git 访问代码仓库（如 GitHub、GitLab、Codeup 等）。
            """)

            docSubtitle("核心文件")
            docTable([
                ("~/.ssh/", "SSH 配置目录，权限应为 700"),
                ("~/.ssh/config", "SSH 客户端配置文件，定义 Host 别名和连接参数"),
                ("~/.ssh/known_hosts", "已知主机指纹列表，防止中间人攻击"),
                ("~/.ssh/id_ed25519", "Ed25519 私钥文件（推荐算法）"),
                ("~/.ssh/id_ed25519.pub", "对应的公钥文件，需添加到 Git 平台"),
                ("~/.ssh/authorized_keys", "允许登录本机的公钥列表（服务器端使用）"),
            ])

            docSubtitle("连接流程")
            docNumberedList([
                "客户端通过 DNS 解析目标主机 → 建立 TCP 连接",
                "协商 SSH 协议版本和加密算法（密钥交换）",
                "验证服务器指纹（known_hosts 检查）",
                "客户端用私钥签名 → 服务器用公钥验签 → 认证完成",
                "建立加密通道，开始传输数据",
            ])

            docTip("使用本工具的「连通测试」tab 可以快速测试，「诊断连接」（右键 Host 配置卡片）可以查看完整的连接步骤分析。")
        }
    }

    // MARK: - Config Fields

    private var configFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("~/.ssh/config 字段详解")

            docParagraph("SSH config 文件以 Host 块为单位组织，每个 Host 块定义一组连接参数。Host * 为全局默认配置。")

            docSubtitle("基础字段")
            fieldDoc(
                name: "Host",
                example: "Host codeup-personal",
                description: "别名，用于 ssh 命令和 git remote URL。可以是任意名称，不需要是真实域名。支持通配符 * 和 ?。",
                important: "这是配置块的入口标识，必须唯一。"
            )
            fieldDoc(
                name: "HostName",
                example: "HostName codeup.aliyun.com",
                description: "真实的主机名或 IP 地址。当 Host 使用别名时，HostName 指定实际连接的服务器。",
                important: nil
            )
            fieldDoc(
                name: "User",
                example: "User git",
                description: "登录用户名。Git 平台（GitHub / GitLab / Codeup）统一使用 git。",
                important: nil
            )
            fieldDoc(
                name: "Port",
                example: "Port 22",
                description: "SSH 端口，默认 22。某些企业网络或自建 GitLab 可能使用其他端口（如 2222）。",
                important: nil
            )

            docSubtitle("密钥认证字段")
            fieldDoc(
                name: "IdentityFile",
                example: "IdentityFile ~/.ssh/id_ed25519",
                description: "指定此 Host 使用的私钥文件路径。支持 ~ 代表 home 目录。可以指定多个，SSH 会依次尝试。",
                important: "路径错误或文件不存在会导致认证失败。"
            )
            fieldDoc(
                name: "IdentitiesOnly",
                example: "IdentitiesOnly yes",
                description: "设为 yes 时，SSH 只使用 IdentityFile 指定的密钥，忽略 SSH Agent 中缓存的其他密钥。",
                important: "多账号场景必须设为 yes，否则可能使用错误的密钥。"
            )
            fieldDoc(
                name: "IdentityAgent",
                example: "IdentityAgent none",
                description: """
                控制 SSH Agent socket 路径。设为 none 可完全禁用 SSH Agent。\n\
                SSH Agent 是一个后台守护进程，会缓存所有曾经使用过的私钥。当你有多个账号时，\
                Agent 可能自动提供错误账号的密钥，导致认证失败或登录到错误账号。
                """,
                important: "多账号场景的关键字段。设为 none 配合 IdentitiesOnly yes 可确保每个 Host 只使用指定的密钥。"
            )
            fieldDoc(
                name: "AddKeysToAgent",
                example: "AddKeysToAgent yes",
                description: "认证成功后自动将密钥添加到 SSH Agent 缓存。macOS 可设为 yes。",
                important: nil
            )
            fieldDoc(
                name: "UseKeychain",
                example: "UseKeychain yes",
                description: "macOS 专属。将密钥密码保存到系统 Keychain，避免每次输入。",
                important: "仅 macOS 支持，Linux 忽略此字段。"
            )

            docSubtitle("连接控制字段")
            fieldDoc(
                name: "PreferredAuthentications",
                example: "PreferredAuthentications publickey",
                description: "指定尝试的认证方式及顺序。常见值: publickey, password, keyboard-interactive。",
                important: nil
            )
            fieldDoc(
                name: "ServerAliveInterval",
                example: "ServerAliveInterval 60",
                description: "每隔 N 秒发送一个心跳包保持连接。适合网络不稳定或有超时断开的场景。",
                important: nil
            )
            fieldDoc(
                name: "ServerAliveCountMax",
                example: "ServerAliveCountMax 3",
                description: "心跳包无响应达到 N 次后断开连接。配合 ServerAliveInterval 使用。",
                important: nil
            )
            fieldDoc(
                name: "ConnectTimeout",
                example: "ConnectTimeout 10",
                description: "连接超时秒数，超过后放弃连接。",
                important: nil
            )
            fieldDoc(
                name: "StrictHostKeyChecking",
                example: "StrictHostKeyChecking ask",
                description: "控制服务器指纹验证策略。ask（默认）= 首次询问，yes = 必须在 known_hosts 中，no = 自动接受。",
                important: "生产环境不建议设为 no，存在安全风险。"
            )
            fieldDoc(
                name: "Compression",
                example: "Compression yes",
                description: "启用传输压缩。对慢速网络有帮助，但在高速网络上可能增加 CPU 开销。",
                important: nil
            )
            fieldDoc(
                name: "LogLevel",
                example: "LogLevel ERROR",
                description: "日志级别。QUIET, FATAL, ERROR, INFO, VERBOSE, DEBUG, DEBUG1, DEBUG2, DEBUG3。",
                important: nil
            )

            docSubtitle("代理和转发")
            fieldDoc(
                name: "ProxyCommand",
                example: "ProxyCommand nc -X 5 -x 127.0.0.1:1080 %h %p",
                description: "通过代理连接。%h 和 %p 会替换为目标主机和端口。常用于穿越防火墙。",
                important: nil
            )
            fieldDoc(
                name: "ProxyJump",
                example: "ProxyJump bastion",
                description: "通过跳板机连接（SSH -J 语法糖）。bastion 是另一个 Host 配置的别名。",
                important: nil
            )
            fieldDoc(
                name: "ForwardAgent",
                example: "ForwardAgent yes",
                description: "转发本地 SSH Agent 到远程主机，使远程主机可以使用你本地的密钥。",
                important: "存在安全风险 — 远程主机管理员可以使用你的密钥。只在受信任的服务器上启用。"
            )
            fieldDoc(
                name: "LocalForward",
                example: "LocalForward 8080 localhost:80",
                description: "本地端口转发。将本地 8080 映射到远程的 localhost:80。",
                important: nil
            )
            fieldDoc(
                name: "RemoteForward",
                example: "RemoteForward 9090 localhost:3000",
                description: "远程端口转发。将远程 9090 映射到本地的 localhost:3000。",
                important: nil
            )
        }
    }

    // MARK: - Key Types

    private var keyTypesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("SSH 密钥类型")

            docParagraph("SSH 密钥是一对数学上关联的文件：私钥（保密）和公钥（公开）。不同算法在安全性、性能和兼容性上有差异。")

            docSubtitle("算法对比")

            keyTypeDoc(
                name: "Ed25519 (推荐)",
                bits: "256 位固定",
                pros: "最安全、最快、密钥最短",
                cons: "较旧的系统可能不支持 (OpenSSH < 6.5)",
                usage: "新项目首选，除非目标系统明确不支持"
            )
            keyTypeDoc(
                name: "RSA",
                bits: "2048 / 4096 位",
                pros: "兼容性最好，几乎所有系统都支持",
                cons: "密钥长、签名慢，2048 位以下不安全",
                usage: "需要兼容老系统时使用，至少 4096 位"
            )
            keyTypeDoc(
                name: "ECDSA",
                bits: "256 / 384 / 521 位",
                pros: "性能和安全性均衡",
                cons: "依赖 NIST 曲线（部分安全社区存疑）",
                usage: "一般不推荐，优先选 Ed25519"
            )
            keyTypeDoc(
                name: "DSA (已废弃)",
                bits: "1024 位固定",
                pros: "无",
                cons: "OpenSSH 7.0 已默认禁用，1024 位不安全",
                usage: "不要使用"
            )

            docSubtitle("密钥密码 (Passphrase)")
            docParagraph("""
            Passphrase 是私钥文件的加密密码。即使私钥文件泄露，没有密码也无法使用。\
            强烈建议设置。配合 macOS Keychain (UseKeychain yes + AddKeysToAgent yes)，只需首次输入。
            """)
        }
    }

    // MARK: - Multi-Account

    private var multiAccountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("同一平台多账号配置")

            docParagraph("""
            当你在同一个 Git 平台（如 GitHub、Codeup）有多个账号时，需要为每个账号创建不同的 Host 别名，\
            使用不同的密钥文件，并正确配置 SSH Agent 行为。
            """)

            docSubtitle("配置示例")
            docCodeBlock("""
            # 个人账号
            Host github-personal
                HostName github.com
                User git
                IdentityFile ~/.ssh/id_ed25519_personal
                IdentitiesOnly yes
                IdentityAgent none

            # 公司账号
            Host github-work
                HostName github.com
                User git
                IdentityFile ~/.ssh/id_ed25519_work
                IdentitiesOnly yes
                IdentityAgent none
            """)

            docSubtitle("关键三件套")
            docNumberedList([
                "IdentityFile — 每个账号指向不同的密钥文件",
                "IdentitiesOnly yes — 只用指定密钥，不让 SSH 自动尝试其他",
                "IdentityAgent none — 禁用 Agent 缓存，防止串号",
            ])

            docSubtitle("使用方式")
            docParagraph("克隆仓库时使用 Host 别名替代真实域名：")
            docCodeBlock("""
            # 个人项目
            git clone git@github-personal:myuser/repo.git

            # 公司项目
            git clone git@github-work:company/repo.git
            """)

            docSubtitle("已有仓库切换")
            docParagraph("对已经 clone 过的仓库，修改 remote URL：")
            docCodeBlock("""
            git remote set-url origin git@github-work:company/repo.git
            """)

            docTip("也可以使用「仓库扫描」tab 批量查看和切换已有仓库的 remote URL。或使用 Git URL 重写 (insteadOf) 自动转换。")
        }
    }

    // MARK: - known_hosts

    private var knownHostsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("known_hosts 说明")

            docParagraph("""
            ~/.ssh/known_hosts 存储了你连接过的每台服务器的公钥指纹。这是 SSH 的"信任锚"——\
            防止中间人冒充服务器。
            """)

            docSubtitle("工作原理")
            docNumberedList([
                "首次连接 → SSH 提示确认服务器指纹 → 输入 yes → 记录到 known_hosts",
                "后续连接 → SSH 自动比对指纹 → 匹配则继续，不匹配则报错",
                "指纹不匹配 = 服务器可能被替换（或服务商更新了密钥）",
            ])

            docSubtitle("常见问题")
            docTable([
                ("WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED", "服务器密钥变更。确认是正常变更后，删除旧记录即可"),
                ("Host key verification failed", "known_hosts 中的指纹不匹配。先确认安全，再清理"),
                ("重复条目", "同一服务器通过域名和 IP 连接会产生多条记录，属正常情况"),
            ])

            docTip("使用「known_hosts」tab 可以查看、搜索和管理所有条目，还能自动检测重复记录。")
        }
    }

    // MARK: - Git Integration

    private var gitIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Git 与 SSH 集成")

            docSubtitle("Git URL 格式")
            docTable([
                ("SSH 格式", "git@github.com:user/repo.git"),
                ("SSH 别名格式", "git@my-alias:user/repo.git"),
                ("HTTPS 格式", "https://github.com/user/repo.git"),
            ])

            docSubtitle("URL 重写 (insteadOf)")
            docParagraph("""
            Git 的 url.*.insteadOf 机制可以自动将一个 URL 前缀替换为另一个。\
            适合将默认域名透明地替换为 SSH Host 别名。
            """)
            docCodeBlock("""
            # ~/.gitconfig
            [url "git@github-work:"]
                insteadOf = git@github.com:

            # 效果: git clone git@github.com:org/repo.git
            # 实际连接: git@github-work:org/repo.git
            """)

            docSubtitle("includeIf 条件配置")
            docParagraph("""
            Git 可以根据仓库所在目录自动使用不同的用户身份：
            """)
            docCodeBlock("""
            # ~/.gitconfig
            [includeIf "gitdir:~/work/"]
                path = ~/.gitconfig-work

            # ~/.gitconfig-work
            [user]
                name = 张三（公司）
                email = zhangsan@company.com
            """)

            docTip("使用「Git 身份」tab 可以可视化管理 includeIf 配置。")
        }
    }

    // MARK: - Troubleshooting

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("常见问题排查")

            troubleshootItem(
                problem: "Permission denied (publickey)",
                causes: [
                    "公钥未添加到 Git 平台",
                    "IdentityFile 路径错误",
                    "多账号场景下 SSH Agent 提供了错误的密钥",
                    "私钥文件权限不是 600",
                ],
                solutions: [
                    "确认公钥已上传: cat ~/.ssh/xxx.pub → 复制到平台设置",
                    "检查 config 中 IdentityFile 路径是否正确",
                    "设置 IdentityAgent none + IdentitiesOnly yes",
                    "修复权限: chmod 600 ~/.ssh/id_ed25519",
                ]
            )

            troubleshootItem(
                problem: "ssh: connect to host xxx port 22: Connection refused",
                causes: [
                    "服务器 SSH 未启动或端口不是 22",
                    "防火墙拦截",
                    "HostName 配置错误",
                ],
                solutions: [
                    "确认服务器 SSH 端口，可能需要配置 Port 字段",
                    "检查本地防火墙或 VPN 设置",
                    "在「诊断连接」中查看 DNS 解析结果",
                ]
            )

            troubleshootItem(
                problem: "Connection timed out",
                causes: [
                    "网络不通或 DNS 无法解析",
                    "代理设置问题",
                    "服务器在防火墙后",
                ],
                solutions: [
                    "ping 目标主机检查网络",
                    "检查是否需要 ProxyCommand 或 ProxyJump",
                    "尝试关闭 VPN 后重试",
                ]
            )

            troubleshootItem(
                problem: "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED",
                causes: [
                    "服务器迁移或重装后密钥变更",
                    "服务商更新了主机密钥",
                    "（罕见）中间人攻击",
                ],
                solutions: [
                    "确认是合法变更后，在「known_hosts」tab 删除旧记录",
                    "或执行 ssh-keygen -R <host> 删除",
                ]
            )

            troubleshootItem(
                problem: "多账号串号（提交用错账号）",
                causes: [
                    "SSH Agent 缓存了多个密钥并自动选择",
                    "未配置 IdentityAgent none",
                    "Git user.name/email 未区分",
                ],
                solutions: [
                    "为每个账号配置独立 Host 别名 + 密钥",
                    "设置 IdentityAgent none + IdentitiesOnly yes",
                    "使用 includeIf 按目录区分 Git 身份",
                ]
            )

            docSubtitle("诊断命令速查")
            docCodeBlock("""
            # 测试连接
            ssh -T git@github.com

            # 详细诊断（-vvv 最详细）
            ssh -vvv -T git@github.com

            # 查看 Agent 中缓存的密钥
            ssh-add -l

            # 清空 Agent 缓存
            ssh-add -D

            # 查看密钥指纹
            ssh-keygen -lf ~/.ssh/id_ed25519.pub
            """)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("文件权限要求")

            docParagraph("SSH 对文件权限有严格要求。权限过于宽松会导致 SSH 拒绝使用密钥文件。")

            docSubtitle("权限一览")
            docTable([
                ("~/.ssh/", "700 (drwx-----) — 只有所有者可读写执行"),
                ("~/.ssh/config", "600 (-rw-------) — 只有所有者可读写"),
                ("~/.ssh/id_*（私钥）", "600 (-rw-------) — 只有所有者可读写"),
                ("~/.ssh/id_*.pub（公钥）", "644 (-rw-r--r--) — 所有人可读"),
                ("~/.ssh/known_hosts", "644 (-rw-r--r--) — 所有人可读"),
                ("~/.ssh/authorized_keys", "600 (-rw-------) — 只有所有者可读写"),
            ])

            docSubtitle("快速修复")
            docCodeBlock("""
            chmod 700 ~/.ssh
            chmod 600 ~/.ssh/config
            chmod 600 ~/.ssh/id_*
            chmod 644 ~/.ssh/*.pub
            """)

            docTip("本工具的状态栏会实时检测权限异常，点击「一键修复」可自动修正。")
        }
    }

    // MARK: - Searchable text for filtering

    private func sectionSearchableText(_ section: GuideSection) -> String {
        switch section {
        case .overview: return "SSH 概览 连接流程 known_hosts config 密钥 公钥 私钥"
        case .configFields: return "Host HostName User Port IdentityFile IdentitiesOnly IdentityAgent AddKeysToAgent UseKeychain ProxyCommand ProxyJump ForwardAgent ServerAliveInterval Compression StrictHostKeyChecking"
        case .keyTypes: return "Ed25519 RSA ECDSA DSA 算法 密钥 passphrase 密码"
        case .multiAccount: return "多账号 多用户 GitHub Codeup GitLab 别名 insteadOf"
        case .knownHosts: return "known_hosts 指纹 REMOTE HOST IDENTIFICATION CHANGED 中间人"
        case .gitIntegration: return "Git URL insteadOf includeIf 重写 身份 user.name user.email"
        case .troubleshooting: return "Permission denied Connection refused timeout 串号 诊断 debug"
        case .permissions: return "权限 chmod 700 600 644 drwx"
        }
    }

    // MARK: - Reusable Doc Components

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .padding(.bottom, 4)
    }

    private func docSubtitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .padding(.top, 4)
    }

    private func docParagraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func docCodeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .textSelection(.enabled)
    }

    private func docTip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 12))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.06)))
    }

    private func docTable(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 0) {
                    Text(row.0)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 240, alignment: .leading)
                        .padding(8)
                    Text(row.1)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(index % 2 == 0 ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func docNumberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 20, alignment: .trailing)
                    Text(item)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fieldDoc(name: String, example: String, description: String, important: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
            Text(example)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
            Text(description)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            if let important = important {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 10))
                    Text(important)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func keyTypeDoc(name: String, bits: String, pros: String, cons: String, usage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 16) {
                Label(bits, systemImage: "number")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 10))
                Text(pros).font(.system(size: 11))
            }
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.system(size: 10))
                Text(cons).font(.system(size: 11))
            }
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "arrow.right.circle.fill").foregroundColor(.blue).font(.system(size: 10))
                Text(usage).font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func troubleshootItem(problem: String, causes: [String], solutions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(problem)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.red)

            Text("可能原因:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            ForEach(causes, id: \.self) { cause in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundColor(.orange)
                    Text(cause).font(.system(size: 11))
                }
                .padding(.leading, 8)
            }

            Text("解决方案:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            ForEach(Array(solutions.enumerated()), id: \.offset) { idx, solution in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(idx + 1).").foregroundColor(.green).font(.system(size: 11, weight: .medium))
                    Text(solution).font(.system(size: 11))
                }
                .padding(.leading, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
