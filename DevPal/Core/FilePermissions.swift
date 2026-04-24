import Foundation

/// Utility for checking and fixing SSH file permissions
struct FilePermissions {
    
    struct PermissionInfo {
        let path: String
        let current: String    // e.g. "644"
        let expected: String   // e.g. "600"
        var isCorrect: Bool { current == expected }
    }

    /// Get octal permission string for a file
    static func octalPermissions(at path: String) -> String? {
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: path)
        } catch {
            return nil
        }
        guard let posix = attrs[.posixPermissions] as? NSNumber else { return nil }
        return String(format: "%o", posix.intValue)
    }

    /// Check ~/.ssh/ directory permission (should be 700)
    static func checkSSHDirectory() -> PermissionInfo? {
        let path = NSHomeDirectory() + "/.ssh"
        guard let perms = octalPermissions(at: path) else { return nil }
        return PermissionInfo(path: path, current: perms, expected: "700")
    }

    /// Check a private key file permission (should be 600)
    static func checkPrivateKey(at path: String) -> PermissionInfo {
        let perms = octalPermissions(at: path) ?? "unknown"
        return PermissionInfo(path: path, current: perms, expected: "600")
    }

    /// Fix permission for a file
    static func fix(at path: String, to octal: UInt16) throws {
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: octal)]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: path)
    }

    /// Fix SSH directory to 700
    static func fixSSHDirectory() throws {
        try fix(at: NSHomeDirectory() + "/.ssh", to: 0o700)
    }

    /// Fix private key to 600
    static func fixPrivateKey(at path: String) throws {
        try fix(at: path, to: 0o600)
    }
}
