import Foundation

/// Manages full ~/.ssh/ directory backup and restore
class BackupManager {
    static let shared = BackupManager()

    let sshDir = NSHomeDirectory() + "/.ssh"

    /// Create a zip backup of the entire ~/.ssh/ directory
    func createFullBackup(to destination: String? = nil) async throws -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "ssh-backup-\(timestamp).zip"
        let destDir = destination ?? (NSHomeDirectory() + "/Desktop")
        let outputPath = (destDir as NSString).appendingPathComponent(filename)

        let cmd = "cd \(NSHomeDirectory().shellEscaped) && zip -r \(outputPath.shellEscaped) .ssh/ -x '.ssh/.backup/*'"
        let result = try await Shell.run(cmd)

        guard result.succeeded else {
            throw NSError(domain: "BackupManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "备份失败: \(result.stderr)"])
        }

        return outputPath
    }

    /// List auto-backup snapshots from SSHConfigManager
    func listConfigBackups() throws -> [(path: String, date: Date)] {
        try SSHConfigManager.shared.listBackups()
    }

    /// Read backup content for preview
    func readBackup(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Restore a config backup
    func restoreConfigBackup(at path: String) throws {
        try SSHConfigManager.shared.restoreBackup(at: path)
    }
}
