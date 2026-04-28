import SwiftUI

struct EnvManagerView: View {
    @State private var selectedTab: Tab = .variables

    enum Tab: String, CaseIterable {
        case variables = "环境变量", path = "PATH 分析", profiles = "Profile 文件", guide = "帮助文档"
        var icon: String {
            switch self {
            case .variables: return "list.bullet"
            case .path: return "arrow.right.circle"
            case .profiles: return "doc.text"
            case .guide: return "book.fill"
            }
        }
        var subtitle: String {
            switch self {
            case .variables: return "查看当前环境变量"
            case .path: return "检测断链与重复"
            case .profiles: return "编辑 shell 配置"
            case .guide: return "功能使用指南"
            }
        }
    }

    var body: some View {
        PersistentSplitView(id: "env", minWidth: 120, maxWidth: 220, defaultWidth: 150) {
            // Sidebar
            VStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                Text(tab.subtitle)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        } content: {
            // Content
            Group {
                switch selectedTab {
                case .variables: EnvVariablesTab()
                case .path: PathAnalysisTab()
                case .profiles: ProfilesTab()
                case .guide: EnvGuideTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Variables Tab

private struct EnvVariablesTab: View {
    @State private var variables: [EnvVariable] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var revealedValues: Set<String> = []  // var names

    private let sensitiveKeywords = ["TOKEN", "KEY", "SECRET", "PASSWORD", "PASS", "API_KEY", "PRIVATE"]

    var filtered: [EnvVariable] {
        if searchText.isEmpty { return variables }
        let q = searchText.lowercased()
        return variables.filter {
            $0.name.lowercased().contains(q) || $0.value.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索变量名或值...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))

                Spacer()

                Text("\(filtered.count) / \(variables.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button {
                    Task { await load() }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
            }
            .padding(12)

            Divider()

            if isLoading && variables.isEmpty {
                Spacer()
                ProgressView("加载环境变量...")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { v in
                            varRow(v)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .task { await load() }
    }

    private func isSensitive(_ name: String) -> Bool {
        let upper = name.uppercased()
        return sensitiveKeywords.contains(where: { upper.contains($0) })
    }

    private func varRow(_ v: EnvVariable) -> some View {
        let sensitive = isSensitive(v.name)
        let revealed = revealedValues.contains(v.name)
        let displayValue = sensitive && !revealed ? String(repeating: "•", count: min(v.value.count, 20)) : v.value

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(v.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                    if sensitive {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                    if v.isPath {
                        Text("PATH (\(v.pathComponents.count))")
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.purple.opacity(0.12)))
                            .foregroundColor(.purple)
                    }
                }
                Text(displayValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineLimit(v.isPath ? 5 : 3)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 4) {
                if sensitive {
                    Button {
                        if revealed { revealedValues.remove(v.name) }
                        else { revealedValues.insert(v.name) }
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help(revealed ? "隐藏值" : "显示值")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(v.value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制值")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        variables = await EnvManager.loadCurrentEnv()
    }
}

// MARK: - PATH Analysis Tab

private struct PathAnalysisTab: View {
    @State private var pathValue = ""
    @State private var components: [PathEntry] = []
    @State private var isLoading = false

    struct PathEntry: Identifiable, Hashable {
        let id = UUID()
        let path: String
        let exists: Bool
        let isDuplicate: Bool
        let executableCount: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PATH 分析")
                    .font(.system(size: 14, weight: .medium))
                Spacer()

                if !components.isEmpty {
                    let broken = components.filter { !$0.exists }.count
                    let dupes = components.filter { $0.isDuplicate }.count
                    if broken > 0 {
                        Label("\(broken) 个路径不存在", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    if dupes > 0 {
                        Label("\(dupes) 个重复", systemImage: "doc.on.doc.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                    }
                }

                Button {
                    Task { await load() }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
            }
            .padding(12)

            Divider()

            if components.isEmpty {
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Text("PATH 为空")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(components.enumerated()), id: \.element.id) { idx, entry in
                            pathRow(idx: idx, entry: entry)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .task { await load() }
    }

    private func pathRow(idx: Int, entry: PathEntry) -> some View {
        HStack(spacing: 8) {
            Text("\(idx + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 26, alignment: .trailing)

            // Status icon
            if !entry.exists {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
                    .help("路径不存在")
            } else if entry.isDuplicate {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                    .help("重复路径")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            }

            Text(entry.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(entry.exists ? .primary : .secondary)
                .strikethrough(!entry.exists)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if entry.exists {
                Text("\(entry.executableCount) 可执行")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.path, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("复制路径")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(entry.exists ? (entry.isDuplicate ? Color.orange.opacity(0.05) : Color.clear) : Color.red.opacity(0.05))
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let env = await EnvManager.loadCurrentEnv()
        guard let path = env.first(where: { $0.name == "PATH" }) else {
            components = []
            return
        }
        pathValue = path.value

        let raw = path.pathComponents
        var seen: [String: Int] = [:]
        for p in raw { seen[p, default: 0] += 1 }
        let dupePaths = Set(seen.filter { $0.value > 1 }.map { $0.key })

        var entries: [PathEntry] = []
        for p in raw {
            let exists = FileManager.default.fileExists(atPath: p)
            var execCount = 0
            if exists {
                if let items = try? FileManager.default.contentsOfDirectory(atPath: p) {
                    execCount = items.filter { item in
                        let full = "\(p)/\(item)"
                        return FileManager.default.isExecutableFile(atPath: full)
                    }.count
                }
            }
            entries.append(PathEntry(
                path: p,
                exists: exists,
                isDuplicate: dupePaths.contains(p),
                executableCount: execCount
            ))
        }
        components = entries
    }
}

// MARK: - Profiles Tab

private struct ProfilesTab: View {
    @State private var profiles: [ShellProfile] = []
    @State private var selectedProfile: ShellProfile?
    @State private var content = ""
    @State private var originalContent = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showSaveConfirm = false
    @State private var sourcing = false

    var hasChanges: Bool { content != originalContent }

    var body: some View {
        PersistentSplitView(id: "profiles", minWidth: 140, maxWidth: 260, defaultWidth: 180) {
            // Left: profile list
            VStack(spacing: 0) {
                Text("Profile 文件")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(profiles) { profile in
                            Button {
                                if hasChanges {
                                    errorMessage = "有未保存的修改"
                                    return
                                }
                                selectedProfile = profile
                                loadProfile(profile)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: profile.shell.icon)
                                        .font(.system(size: 11))
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack {
                                            Text(profile.name)
                                                .font(.system(size: 12, weight: .medium))
                                            if !profile.exists {
                                                Text("不存在")
                                                    .font(.system(size: 9))
                                                    .padding(.horizontal, 3)
                                                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Text(profile.shell.rawValue)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(selectedProfile?.path == profile.path ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            } content: {
            // Right: editor
            VStack(spacing: 0) {
                if let profile = selectedProfile {
                    HStack {
                        Text(profile.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        if hasChanges {
                            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(.orange)
                            Text("已修改").font(.system(size: 10)).foregroundColor(.orange)
                        }
                        Spacer()
                        Button("撤销") { content = originalContent }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(!hasChanges)
                        Button {
                            showSaveConfirm = true
                        } label: {
                            Label("保存", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!hasChanges || saving)
                        .keyboardShortcut("s", modifiers: .command)

                        Button {
                            Task { await sourceProfile() }
                        } label: {
                            Label(sourcing ? "加载中..." : "重新加载", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!profile.exists || hasChanges || sourcing)
                        .help("执行 source \(profile.name) 使更改在当前环境生效")
                    }
                    .padding(10)

                    Divider()

                    if let error = errorMessage { messageBar(error, isError: true) }
                    if let success = successMessage { messageBar(success, isError: false) }

                    if profile.exists || hasChanges {
                        TextEditor(text: $content)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(4)
                    } else {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                            Text("文件不存在")
                                .foregroundColor(.secondary)
                            Button("创建空文件") {
                                content = "# Created by DevPal\n"
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                    }
                } else {
                    Spacer()
                    Text("选择左侧 Profile 文件进行编辑")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            profiles = EnvManager.discoverProfiles()
            if let first = profiles.first(where: { $0.exists }) {
                selectedProfile = first
                loadProfile(first)
            }
        }
        .alert("保存 Profile 文件？", isPresented: $showSaveConfirm) {
            Button("取消", role: .cancel) { }
            Button("保存") { Task { await save() } }
        } message: {
            Text("将覆写 \(selectedProfile?.name ?? "")。变更前会自动备份到同名 .devpal.bak 文件。")
        }
    }

    private func messageBar(_ text: String, isError: Bool) -> some View {
        HStack {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(text).font(.system(size: 12))
            Spacer()
            Button {
                errorMessage = nil
                successMessage = nil
            } label: { Image(systemName: "xmark").font(.system(size: 10)) }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
    }

    private func loadProfile(_ profile: ShellProfile) {
        content = EnvManager.readProfile(profile)
        originalContent = content
        errorMessage = nil
        successMessage = nil
    }

    private func save() async {
        guard let profile = selectedProfile else { return }
        saving = true
        defer { saving = false }

        do {
            try EnvManager.writeProfile(profile, content: content)
            originalContent = content
            successMessage = "已保存。新终端会话生效，或点击「重新加载」立即生效"
            // Refresh profiles list (file may have just been created)
            profiles = EnvManager.discoverProfiles()
        } catch {
            errorMessage = "保存失败: \(error.localizedDescription)"
        }
    }

    private func sourceProfile() async {
        guard let profile = selectedProfile else { return }
        sourcing = true
        defer { sourcing = false }
        errorMessage = nil
        successMessage = nil

        do {
            let result = try await Shell.run("source \(profile.path) 2>&1", timeout: 10)
            if result.succeeded {
                successMessage = "已执行 source \(profile.name)。DevPal 内的环境变量视图已刷新。"
            } else {
                let stderr = result.stderr.isEmpty ? result.stdout : result.stderr
                errorMessage = "source 失败: \(stderr.prefix(300))"
            }
        } catch {
            errorMessage = "source 失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - Guide Tab

private struct EnvGuideTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text("环境变量与 PATH 使用指南")
                    .font(.system(size: 20, weight: .bold))

                // What are env vars
                guideSection(
                    title: "什么是环境变量？",
                    icon: "list.bullet",
                    content: """
                    环境变量是操作系统提供给所有程序的「全局配置」。\
                    每个终端会话启动时，系统会从 profile 文件中加载一组 KEY=VALUE 形式的变量。\
                    程序可以读取这些变量来决定自己的行为。

                    **日常开发中常见的环境变量：**
                    """
                )

                guideTable([
                    ("HOME", "用户主目录路径，如 /Users/x"),
                    ("PATH", "系统查找可执行文件的目录列表（下方详解）"),
                    ("SHELL", "当前使用的 shell，如 /bin/zsh"),
                    ("LANG / LC_*", "系统语言和编码设置"),
                    ("JAVA_HOME", "Java JDK 安装路径"),
                    ("GOPATH / GOROOT", "Go 语言工作目录和安装路径"),
                    ("NODE_ENV", "Node.js 运行模式 (development / production)"),
                    ("EDITOR", "默认文本编辑器 (vim / code / nano)"),
                    ("HTTP_PROXY / HTTPS_PROXY", "网络代理地址"),
                    ("API_KEY / SECRET_*", "API 密钥等敏感信息（注意安全）"),
                ])

                guideTip("「环境变量」tab 会启动一个登录 shell 来读取真实环境，展示的是实际生效的值。带有 TOKEN / KEY / SECRET 等关键词的变量会自动遮罩，点击眼睛图标可显示。")

                Divider().padding(.vertical, 4)

                // What is PATH
                guideSection(
                    title: "PATH 是什么？为什么重要？",
                    icon: "arrow.right.circle",
                    content: """
                    PATH 是最重要的环境变量之一。当你在终端输入一个命令（如 `git`、`node`、`python`），\
                    系统会按 PATH 中列出的目录**从前到后逐个查找**，找到第一个匹配的可执行文件就执行它。

                    **这意味着 PATH 中目录的顺序决定了命令的优先级。**
                    """
                )

                guideCodeBlock("""
                # 假设 PATH 是：
                /usr/local/bin:/usr/bin:/bin

                # 输入 git 时，系统查找顺序：
                1. /usr/local/bin/git  ← 找到就用这个
                2. /usr/bin/git
                3. /bin/git
                """)

                guideSubtitle("PATH 分析能帮你发现什么？")

                guideNumberedList([
                    "**不存在的路径（红色标记）** — 卸载了某个工具但忘了清理 PATH，不影响功能但拖慢命令查找速度",
                    "**重复的路径（橙色标记）** — 多个 profile 文件重复添加了同一路径，容易在 PATH 越来越长后引起混乱",
                    "**可执行文件数量** — 帮你理解每个目录提供了多少命令，排查「为什么 which python 指向了意外的版本」",
                    "**优先级顺序** — 序号越小优先级越高。如果两个目录都有 python，排在前面的那个会被优先使用",
                ])

                guideTip("常见场景：安装了 nvm / pyenv / Homebrew 后，它们会往 PATH 前面插入自己的目录。如果发现命令版本不对，检查 PATH 顺序是最快的排查方式。")

                Divider().padding(.vertical, 4)

                // Profile files
                guideSection(
                    title: "Profile 文件是什么？",
                    icon: "doc.text",
                    content: """
                    Profile 文件是 shell 启动时自动执行的脚本。\
                    环境变量、PATH 修改、alias 别名、自定义函数都写在里面。
                    """
                )

                guideTable([
                    (".zshrc", "zsh 交互式 shell 每次启动都会加载（最常编辑的文件）"),
                    (".zprofile", "zsh 登录 shell 启动时加载（类似 .bash_profile）"),
                    (".zshenv", "zsh 所有模式都会加载（包括脚本执行），慎用"),
                    (".bashrc", "bash 交互式 shell 加载"),
                    (".bash_profile", "bash 登录 shell 加载"),
                    (".profile", "通用 profile，bash 和 sh 都会读取"),
                ])

                guideSubtitle("加载顺序 (zsh)")
                guideCodeBlock("""
                1. /etc/zshenv      → .zshenv        # 所有情况
                2. /etc/zprofile    → .zprofile       # 仅登录 shell
                3. /etc/zshrc       → .zshrc          # 仅交互式
                4. /etc/zlogin      → .zlogin         # 仅登录 shell（在 .zshrc 之后）
                """)

                guideTip("修改 profile 后需要 source ~/.zshrc 或新开终端才生效。本工具编辑保存前会自动备份为 .devpal.bak 文件。")

                Divider().padding(.vertical, 4)

                // Practical examples
                guideSection(
                    title: "实用示例",
                    icon: "wrench.and.screwdriver",
                    content: "以下是开发中最常见的 profile 配置："
                )

                guideCodeBlock("""
                # Homebrew (Apple Silicon)
                eval "$(/opt/homebrew/bin/brew shellenv)"

                # nvm (Node 版本管理)
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

                # Go
                export GOPATH=$HOME/go
                export PATH=$GOPATH/bin:$PATH

                # Java (多版本切换)
                export JAVA_HOME=$(/usr/libexec/java_home -v 17)

                # 代理设置
                export HTTP_PROXY=http://127.0.0.1:7890
                export HTTPS_PROXY=$HTTP_PROXY

                # 常用 alias
                alias ll='ls -la'
                alias gs='git status'
                alias gp='git pull'
                """)

                Divider().padding(.vertical, 4)

                guideSection(
                    title: "安全提示",
                    icon: "lock.shield",
                    content: """
                    环境变量中经常包含敏感信息（API Key、Token、数据库密码等）。注意：
                    """
                )

                guideNumberedList([
                    "不要将含敏感信息的 .env 文件提交到 Git（加到 .gitignore）",
                    "子进程会继承父进程的所有环境变量 — 注意不要在不受信任的环境中暴露",
                    "使用 `printenv` 或本工具可以查看当前所有已导出的变量",
                    "本工具自动识别含 TOKEN / KEY / SECRET / PASSWORD 的变量名并遮罩显示",
                ])
            }
            .padding(24)
        }
    }

    // MARK: - Components

    private func guideSection(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(content)
                .font(.system(size: 13))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func guideSubtitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .padding(.top, 4)
    }

    private func guideCodeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .textSelection(.enabled)
    }

    private func guideTip(_ text: String) -> some View {
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

    private func guideTable(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 0) {
                    Text(row.0)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 200, alignment: .leading)
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

    private func guideNumberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 20, alignment: .trailing)
                    Text(LocalizedStringKey(item))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
