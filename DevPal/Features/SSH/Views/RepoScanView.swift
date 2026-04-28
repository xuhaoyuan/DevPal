import SwiftUI

/// Git repository scanning view - shows which repo uses which SSH config/key
struct RepoScanView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var scanPath = "~/projects"
    @State private var repos: [GitRepoScanner.ScannedRepo] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var searchText = ""
    @State private var switchingRepo: GitRepoScanner.ScannedRepo?
    @State private var selectedHost = ""

    private let scanner = GitRepoScanner.shared

    var filteredRepos: [GitRepoScanner.ScannedRepo] {
        if searchText.isEmpty { return repos }
        let q = searchText.lowercased()
        return repos.filter {
            $0.name.lowercased().contains(q) ||
            $0.remoteHost.lowercased().contains(q) ||
            $0.matchedConfig?.lowercased().contains(q) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text("Git 仓库扫描")
                    .font(.system(size: 14, weight: .medium))
                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                    TextField("扫描目录", text: $scanPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 180)
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.prompt = "选择"
                        panel.message = "选择要扫描的文件夹"
                        if let expanded = scanPath.isEmpty ? nil : NSString(string: scanPath).expandingTildeInPath as String? {
                            panel.directoryURL = URL(fileURLWithPath: expanded)
                        }
                        if panel.runModal() == .OK, let url = panel.url {
                            scanPath = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                        }
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("选择文件夹")
                }

                Button {
                    Task { await scan() }
                } label: {
                    if isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("扫描", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isScanning || scanPath.isEmpty)
            }
            .padding(12)

            Divider()

            if !hasScanned {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("扫描本地目录，查看每个 Git 仓库使用的 SSH 配置")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    Text("可以帮你快速发现哪些仓库的 remote URL 需要更新")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
                Spacer()
            } else if repos.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("未找到 Git 仓库")
                        .foregroundColor(.secondary)
                    Text("请确认路径正确，或尝试增大扫描深度")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索仓库...", text: $searchText)
                        .textFieldStyle(.plain)
                    Text("\(repos.count) 个仓库")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Stats bar
                statsBar

                // Repo list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredRepos) { repo in
                            repoRow(repo)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .sheet(item: $switchingRepo) { repo in
            switchRemoteSheet(repo: repo)
        }
    }

    // MARK: - Stats

    private var statsBar: some View {
        let sshCount = repos.filter { $0.isSSH }.count
        let httpsCount = repos.filter { !$0.isSSH }.count
        let unmatchedCount = repos.filter { $0.isSSH && $0.matchedConfig == nil }.count

        return HStack(spacing: 12) {
            Label("\(sshCount) SSH", systemImage: "lock.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            Label("\(httpsCount) HTTPS", systemImage: "globe")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            if unmatchedCount > 0 {
                Label("\(unmatchedCount) 未匹配 Host", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Repo Row

    private func repoRow(_ repo: GitRepoScanner.ScannedRepo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(repo.name)
                    .font(.system(size: 13, weight: .medium))

                // Protocol badge
                Text(repo.isSSH ? "SSH" : "HTTPS")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3)
                        .fill(repo.isSSH ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12)))
                    .foregroundColor(repo.isSSH ? .blue : .secondary)

                Spacer()

                // Switch button for SSH repos
                if repo.isSSH {
                    Button("切换 Host") {
                        switchingRepo = repo
                        selectedHost = repo.matchedConfig ?? ""
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            // Remote URL
            Text(repo.remoteURL)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 12) {
                // Host mapping
                if repo.isSSH {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                        Text(repo.remoteHost)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(.secondary)

                    if let config = repo.matchedConfig {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Image(systemName: "gearshape")
                                .font(.system(size: 10))
                            Text(config)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundColor(.accentColor)
                    } else {
                        Text("未匹配 Host 配置")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }

                    if let key = repo.matchedKey {
                        HStack(spacing: 4) {
                            Image(systemName: "key")
                                .font(.system(size: 10))
                            Text(key)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundColor(.green)
                    }
                }
            }

            // Path
            Text(repo.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - Switch Remote Sheet

    private func switchRemoteSheet(repo: GitRepoScanner.ScannedRepo) -> some View {
        VStack(spacing: 16) {
            Text("切换 SSH Host")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("仓库: \(repo.name)").font(.system(size: 12))
                Text("当前 URL: \(repo.remoteURL)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Picker("选择 Host", selection: $selectedHost) {
                Text("不变").tag("")
                ForEach(viewModel.configs.filter { !$0.isGlobal }) { config in
                    Text("\(config.host) → \(config.hostName)")
                        .tag(config.host)
                }
            }
            .pickerStyle(.radioGroup)
            .font(.system(size: 12))

            if !selectedHost.isEmpty {
                Text("新 URL: git@\(selectedHost):\(repo.remotePath).git")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.green)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }

            HStack {
                Button("取消") { switchingRepo = nil }
                Spacer()
                Button("确认切换") {
                    Task {
                        do {
                            try await scanner.switchRemote(
                                repoPath: repo.path,
                                newHost: selectedHost,
                                remotePath: repo.remotePath
                            )
                            viewModel.successMessage = "\(repo.name) remote URL 已切换"
                            switchingRepo = nil
                            await scan()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedHost.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450)
    }

    // MARK: - Actions

    private func scan() async {
        isScanning = true
        defer {
            isScanning = false
            hasScanned = true
        }

        let rawRepos = await scanner.scan(directory: scanPath)
        repos = scanner.matchRepos(rawRepos, configs: viewModel.configs)
    }
}
