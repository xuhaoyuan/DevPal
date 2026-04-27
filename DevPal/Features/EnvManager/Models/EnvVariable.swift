import Foundation

/// One environment variable as currently exported in shell
struct EnvVariable: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let value: String
    var isPath: Bool { name == "PATH" || name.hasSuffix("_PATH") || name.hasSuffix("PATH") }
    var pathComponents: [String] {
        guard isPath else { return [] }
        return value.components(separatedBy: ":").filter { !$0.isEmpty }
    }
}

/// Shell profile file (rc/profile)
struct ShellProfile: Identifiable, Hashable {
    let id = UUID()
    let name: String         // .zshrc
    let path: String         // /Users/x/.zshrc
    let exists: Bool
    let shell: ShellKind

    enum ShellKind: String {
        case zsh = "zsh", bash = "bash", fish = "fish", common = "common"
        var icon: String {
            switch self {
            case .zsh: return "terminal"
            case .bash: return "terminal.fill"
            case .fish: return "fish"
            case .common: return "doc.text"
            }
        }
    }
}

enum EnvManager {
    /// Get current shell environment by spawning a login shell
    static func loadCurrentEnv() async -> [EnvVariable] {
        // Use the user's actual login shell to capture exported variables
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // -i interactive, -l login — picks up profile files
        let cmd = "\(shellPath) -ilc env 2>/dev/null"
        guard let result = try? await Shell.run(cmd, timeout: 10) else { return [] }

        return parseEnvOutput(result.stdout)
    }

    /// Parse `env` output into structured variables
    private static func parseEnvOutput(_ output: String) -> [EnvVariable] {
        var vars: [EnvVariable] = []
        var currentName: String?
        var currentValue: String = ""

        for line in output.components(separatedBy: "\n") {
            // A new variable line starts with NAME=value
            // (NAME may contain letters, digits, underscore; must start with letter/_)
            if let eq = line.firstIndex(of: "="), isValidVarName(String(line[..<eq])) {
                // Flush previous
                if let name = currentName {
                    vars.append(EnvVariable(name: name, value: currentValue))
                }
                currentName = String(line[..<eq])
                currentValue = String(line[line.index(after: eq)...])
            } else if currentName != nil {
                // Continuation of multi-line value
                currentValue += "\n" + line
            }
        }
        // Flush last
        if let name = currentName {
            vars.append(EnvVariable(name: name, value: currentValue))
        }

        return vars.sorted { $0.name < $1.name }
    }

    private static func isValidVarName(_ s: String) -> Bool {
        guard let first = s.first, first.isLetter || first == "_" else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: - Profile Files

    static func discoverProfiles() -> [ShellProfile] {
        let home = NSHomeDirectory()
        let candidates: [(String, ShellProfile.ShellKind)] = [
            (".zshrc", .zsh),
            (".zprofile", .zsh),
            (".zshenv", .zsh),
            (".bashrc", .bash),
            (".bash_profile", .bash),
            (".profile", .common),
            (".config/fish/config.fish", .fish),
        ]

        return candidates.map { name, kind in
            let path = "\(home)/\(name)"
            return ShellProfile(
                name: name,
                path: path,
                exists: FileManager.default.fileExists(atPath: path),
                shell: kind
            )
        }
    }

    static func readProfile(_ profile: ShellProfile) -> String {
        guard profile.exists else { return "" }
        return (try? String(contentsOfFile: profile.path, encoding: .utf8)) ?? ""
    }

    static func writeProfile(_ profile: ShellProfile, content: String) throws {
        // Backup before overwriting
        if profile.exists {
            let backupPath = profile.path + ".devpal.bak"
            try? FileManager.default.removeItem(atPath: backupPath)
            try FileManager.default.copyItem(atPath: profile.path, toPath: backupPath)
        }
        try content.write(toFile: profile.path, atomically: true, encoding: .utf8)
    }

    /// Detect path entries that don't exist on disk
    static func brokenPathEntries(_ pathValue: String) -> [String] {
        pathValue.components(separatedBy: ":")
            .filter { !$0.isEmpty }
            .filter { !FileManager.default.fileExists(atPath: $0) }
    }

    /// Detect duplicate path entries
    static func duplicatePathEntries(_ pathValue: String) -> [String] {
        let components = pathValue.components(separatedBy: ":").filter { !$0.isEmpty }
        var seen: [String: Int] = [:]
        for c in components { seen[c, default: 0] += 1 }
        return seen.filter { $0.value > 1 }.map { $0.key }
    }
}
