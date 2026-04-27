import Foundation

/// Manages reading/writing of ~/.ssh/config with safe write strategy
class SSHConfigManager {
    static let shared = SSHConfigManager()

    let configPath: String = NSHomeDirectory() + "/.ssh/config"
    let backupDir: String = NSHomeDirectory() + "/.ssh/.backup"
    private let parser = SSHConfigParser()
    private let maxBackups = 20

    // MARK: - Read

    /// Load all Host configs from ~/.ssh/config
    func loadConfigs() throws -> [SSHHostConfig] {
        try parser.parseFile(at: configPath)
    }

    // MARK: - Write (Safe)

    /// Save configs using the safe write strategy:
    /// 1. Write to temp file
    /// 2. Backup original
    /// 3. Atomic rename
    /// 4. Set permissions
    func saveConfigs(_ configs: [SSHHostConfig]) throws {
        let content = parser.serialize(configs: configs)
        try safeWrite(content)
    }

    /// Add a new host config (append to end)
    func addConfig(_ config: SSHHostConfig) throws {
        var configs = try loadConfigs()
        configs.append(config)
        try saveConfigs(configs)
    }

    /// Update an existing host config by matching host name
    func updateConfig(_ config: SSHHostConfig) throws {
        var configs = try loadConfigs()
        guard let index = configs.firstIndex(where: { $0.host == config.host }) else {
            throw NSError(domain: "SSHConfigManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到要更新的 Host 配置"])
        }
        configs[index] = config
        try saveConfigs(configs)
    }

    /// Remove a host config by host name
    func removeConfig(host: String) throws {
        var configs = try loadConfigs()
        configs.removeAll { $0.host == host }
        try saveConfigs(configs)
    }

    /// Update IdentityFile references when a key is renamed
    func updateKeyReferences(oldPath: String, newPath: String) throws {
        var configs = try loadConfigs()
        var changed = false
        for i in configs.indices {
            // Match both full path and ~/... path
            let oldTilde = oldPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            let newTilde = newPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")

            if configs[i].identityFile == oldPath || configs[i].identityFile == oldTilde {
                configs[i].identityFile = newTilde
                changed = true
            }
        }
        if changed {
            try saveConfigs(configs)
        }
    }

    /// Find which hosts reference a given key path
    func hostsReferencingKey(path: String) throws -> [String] {
        let configs = try loadConfigs()
        let tilePath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return configs.filter {
            $0.identityFile == path || $0.identityFile == tilePath
        }.map { $0.host }
    }

    // MARK: - Safe Write Strategy

    private func safeWrite(_ content: String) throws {
        let fm = FileManager.default
        let sshDir = (configPath as NSString).deletingLastPathComponent

        // Ensure ~/.ssh/ exists
        if !fm.fileExists(atPath: sshDir) {
            try fm.createDirectory(atPath: sshDir, withIntermediateDirectories: true)
            try FilePermissions.fixSSHDirectory()
        }

        // 1. Write to temp file
        let tmpPath = configPath + ".tmp"
        try content.write(toFile: tmpPath, atomically: true, encoding: .utf8)

        // 2. Backup original if it exists
        if fm.fileExists(atPath: configPath) {
            try createBackup()
        }

        // 3. Atomic rename
        if fm.fileExists(atPath: configPath) {
            try fm.removeItem(atPath: configPath)
        }
        try fm.moveItem(atPath: tmpPath, toPath: configPath)

        // 4. Set permissions (config should be 644)
        try FilePermissions.fix(at: configPath, to: 0o644)
    }

    // MARK: - Backup

    /// Create a backup of the current config
    func createBackup() throws {
        let fm = FileManager.default

        if !fm.fileExists(atPath: backupDir) {
            try fm.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = (backupDir as NSString).appendingPathComponent("config.\(timestamp).bak")

        try fm.copyItem(atPath: configPath, toPath: backupPath)

        // Cleanup old backups
        try cleanupOldBackups()
    }

    /// List all config backups, newest first
    func listBackups() throws -> [(path: String, date: Date)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupDir) else { return [] }

        let files = try fm.contentsOfDirectory(atPath: backupDir)
            .filter { $0.hasPrefix("config.") && $0.hasSuffix(".bak") }

        return files.compactMap { file -> (String, Date)? in
            let path = (backupDir as NSString).appendingPathComponent(file)
            let attrs = try? fm.attributesOfItem(atPath: path)
            let date = attrs?[.modificationDate] as? Date ?? Date.distantPast
            return (path, date)
        }.sorted { $0.1 > $1.1 }
    }

    /// Read content of a backup file
    func readBackup(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Restore from a backup file
    func restoreBackup(at path: String) throws {
        let content = try readBackup(at: path)
        try safeWrite(content)
    }

    private func cleanupOldBackups() throws {
        let backups = try listBackups()
        if backups.count > maxBackups {
            let toDelete = backups.suffix(from: maxBackups)
            for backup in toDelete {
                try? FileManager.default.removeItem(atPath: backup.path)
            }
        }
    }
}
