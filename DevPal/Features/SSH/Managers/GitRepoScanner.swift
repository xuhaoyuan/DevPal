import Foundation

/// Scans local directories for Git repositories and maps them to SSH configs
class GitRepoScanner {
    static let shared = GitRepoScanner()

    struct ScannedRepo: Identifiable {
        let id: String  // repo path
        let name: String
        let path: String
        let remoteURL: String
        let remoteHost: String       // host portion from URL (e.g. "codeup.aliyun.com" or "codeup-work")
        let remotePath: String       // org/repo portion
        let matchedConfig: String?   // matched SSH Host alias
        let matchedKey: String?      // matched identity file name
        let isSSH: Bool
    }

    /// Scan a directory recursively for git repos (up to maxDepth)
    func scan(directory: String, maxDepth: Int = 4) async -> [ScannedRepo] {
        let expandedPath = (directory as NSString).expandingTildeInPath
        var repos: [ScannedRepo] = []

        guard let result = try? await Shell.run(
            "find \(expandedPath.shellEscaped) -maxdepth \(maxDepth) -name .git -type d 2>/dev/null"
        ), result.succeeded else {
            return []
        }

        let gitDirs = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }

        for gitDir in gitDirs {
            let repoPath = (gitDir as NSString).deletingLastPathComponent
            if let repo = await loadRepoInfo(at: repoPath) {
                repos.append(repo)
            }
        }

        return repos.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Load info for a single git repo
    private func loadRepoInfo(at path: String) async -> ScannedRepo? {
        guard let result = try? await Shell.run(
            "git -C \(path.shellEscaped) remote get-url origin 2>/dev/null"
        ), result.succeeded else {
            return nil
        }

        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }

        let name = (path as NSString).lastPathComponent
        let (host, repoPath, isSSH) = parseRemoteURL(url)

        return ScannedRepo(
            id: path,
            name: name,
            path: path,
            remoteURL: url,
            remoteHost: host,
            remotePath: repoPath,
            matchedConfig: nil,
            matchedKey: nil,
            isSSH: isSSH
        )
    }

    /// Parse a git remote URL to extract host and path
    /// Supports: git@host:org/repo.git, ssh://git@host/org/repo.git, https://host/org/repo.git
    private func parseRemoteURL(_ url: String) -> (host: String, path: String, isSSH: Bool) {
        // SSH format: git@host:org/repo.git
        if url.contains("@") && url.contains(":") && !url.hasPrefix("http") {
            let parts = url.components(separatedBy: "@")
            if parts.count >= 2 {
                let hostAndPath = parts[1]
                if let colonIdx = hostAndPath.firstIndex(of: ":") {
                    let host = String(hostAndPath[..<colonIdx])
                    let path = String(hostAndPath[hostAndPath.index(after: colonIdx)...])
                        .replacingOccurrences(of: ".git", with: "")
                    return (host, path, true)
                }
            }
        }

        // SSH URL format: ssh://git@host/org/repo.git
        if url.hasPrefix("ssh://") {
            let stripped = url.replacingOccurrences(of: "ssh://", with: "")
            let parts = stripped.components(separatedBy: "@")
            if parts.count >= 2 {
                let hostAndPath = parts[1]
                if let slashIdx = hostAndPath.firstIndex(of: "/") {
                    let host = String(hostAndPath[..<slashIdx])
                    let path = String(hostAndPath[hostAndPath.index(after: slashIdx)...])
                        .replacingOccurrences(of: ".git", with: "")
                    return (host, path, true)
                }
            }
        }

        // HTTPS format: https://host/org/repo.git
        if url.hasPrefix("https://") || url.hasPrefix("http://") {
            let stripped = url.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            if let slashIdx = stripped.firstIndex(of: "/") {
                let host = String(stripped[..<slashIdx])
                let path = String(stripped[stripped.index(after: slashIdx)...])
                    .replacingOccurrences(of: ".git", with: "")
                return (host, path, false)
            }
        }

        return (url, "", false)
    }

    /// Match scanned repos against SSH configs
    func matchRepos(_ repos: [ScannedRepo], configs: [SSHHostConfig]) -> [ScannedRepo] {
        repos.map { repo in
            var matched = repo

            // Find matching config: direct host match or hostName match
            if let config = configs.first(where: { $0.host == repo.remoteHost }) {
                matched = ScannedRepo(
                    id: repo.id, name: repo.name, path: repo.path,
                    remoteURL: repo.remoteURL, remoteHost: repo.remoteHost,
                    remotePath: repo.remotePath,
                    matchedConfig: config.host,
                    matchedKey: config.identityFile.isEmpty ? nil : (config.identityFile as NSString).lastPathComponent,
                    isSSH: repo.isSSH
                )
            } else if let config = configs.first(where: { $0.hostName == repo.remoteHost && !$0.isGlobal }) {
                matched = ScannedRepo(
                    id: repo.id, name: repo.name, path: repo.path,
                    remoteURL: repo.remoteURL, remoteHost: repo.remoteHost,
                    remotePath: repo.remotePath,
                    matchedConfig: config.host,
                    matchedKey: config.identityFile.isEmpty ? nil : (config.identityFile as NSString).lastPathComponent,
                    isSSH: repo.isSSH
                )
            }

            return matched
        }
    }

    /// Change a repo's remote URL to use a different Host alias
    func switchRemote(repoPath: String, newHost: String, remotePath: String) async throws {
        let newURL = "git@\(newHost):\(remotePath).git"
        let result = try await Shell.run(
            "git -C \(repoPath.shellEscaped) remote set-url origin \(newURL.shellEscaped)"
        )
        guard result.succeeded else {
            throw NSError(domain: "GitRepoScanner", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "切换失败: \(result.stderr)"])
        }
    }
}
