import Foundation

/// Manages git URL rewrite rules ([url] insteadOf) in ~/.gitconfig
class GitConfigManager {
    static let shared = GitConfigManager()

    private let gitconfigPath = NSHomeDirectory() + "/.gitconfig"

    // MARK: - URL Rewrite Rules

    struct URLRewriteRule: Identifiable, Equatable {
        let id = UUID()
        var from: String   // insteadOf value (e.g. "git@codeup.aliyun.com:")
        var to: String     // url target (e.g. "git@codeup-work:")
    }

    /// Read all [url "..."] insteadOf rules from git config
    func loadURLRewriteRules() async -> [URLRewriteRule] {
        guard let result = try? await Shell.run("git config --global --get-regexp 'url\\..*\\.insteadof'"),
              result.succeeded else {
            return []
        }

        var rules: [URLRewriteRule] = []
        let lines = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
            // Format: url.<to>.insteadof <from>
            // Example: url.git@codeup-work:.insteadof git@codeup.aliyun.com:myorg/
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let keyPath = String(parts[0]) // url.git@codeup-work:.insteadof
            let from = String(parts[1])

            // Extract the "to" URL from the key path
            // Remove "url." prefix and ".insteadof" suffix
            let stripped = keyPath
                .replacingOccurrences(of: "url.", with: "", options: [], range: keyPath.startIndex..<keyPath.index(keyPath.startIndex, offsetBy: min(4, keyPath.count)))
            if let range = stripped.range(of: ".insteadof", options: .backwards) {
                let to = String(stripped[stripped.startIndex..<range.lowerBound])
                rules.append(URLRewriteRule(from: from, to: to))
            }
        }

        return rules
    }

    /// Add a URL rewrite rule: git config --global url."<to>".insteadOf "<from>"
    func addURLRewriteRule(from: String, to: String) async throws {
        let cmd = "git config --global url.\(to.shellEscaped).insteadOf \(from.shellEscaped)"
        let result = try await Shell.run(cmd)
        guard result.succeeded else {
            throw NSError(domain: "GitConfigManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "添加 URL 重写规则失败: \(result.stderr)"])
        }
    }

    /// Remove a URL rewrite rule
    func removeURLRewriteRule(from: String, to: String) async throws {
        let cmd = "git config --global --unset url.\(to.shellEscaped).insteadOf \(from.shellEscaped)"
        let result = try await Shell.run(cmd)
        guard result.succeeded else {
            throw NSError(domain: "GitConfigManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "删除 URL 重写规则失败: \(result.stderr)"])
        }
    }

    // MARK: - includeIf (Conditional Config)

    struct ConditionalInclude: Identifiable, Equatable {
        let id = UUID()
        var gitdir: String  // e.g. "~/work/"
        var path: String    // e.g. "~/.gitconfig-work"
    }

    /// Read all includeIf.gitdir entries
    func loadConditionalIncludes() async -> [ConditionalInclude] {
        guard let result = try? await Shell.run("git config --global --get-regexp 'includeIf\\.gitdir'"),
              result.succeeded else {
            return []
        }

        var includes: [ConditionalInclude] = []
        let lines = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
            // Format: includeIf.gitdir:~/work/.path ~/.gitconfig-work
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let keyPath = String(parts[0])
            let path = String(parts[1])

            // Extract gitdir from key: includeIf.gitdir:<dir>.path
            if let start = keyPath.range(of: "includeIf.gitdir:"),
               let end = keyPath.range(of: ".path", options: .backwards) {
                let gitdir = String(keyPath[start.upperBound..<end.lowerBound])
                includes.append(ConditionalInclude(gitdir: gitdir, path: path))
            }
        }

        return includes
    }

    /// Add includeIf for directory-specific git config
    func addConditionalInclude(gitdir: String, configPath: String, userName: String?, userEmail: String?) async throws {
        // Create the included config file if user/email provided
        if let name = userName, let email = userEmail {
            let content = "[user]\n    name = \(name)\n    email = \(email)\n"
            let expandedPath = configPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
            try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
        }

        // Add includeIf directive
        let cmd = "git config --global includeIf.gitdir:\(gitdir.shellEscaped).path \(configPath.shellEscaped)"
        let result = try await Shell.run(cmd)
        guard result.succeeded else {
            throw NSError(domain: "GitConfigManager", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "添加条件配置失败: \(result.stderr)"])
        }
    }

    // MARK: - Global User Info

    struct GitUserInfo {
        var name: String
        var email: String
    }

    func loadGlobalUser() async -> GitUserInfo? {
        let nameResult = try? await Shell.run("git config --global user.name")
        let emailResult = try? await Shell.run("git config --global user.email")

        guard let name = nameResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
              let email = emailResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty || !email.isEmpty else {
            return nil
        }

        return GitUserInfo(name: name, email: email)
    }
}
