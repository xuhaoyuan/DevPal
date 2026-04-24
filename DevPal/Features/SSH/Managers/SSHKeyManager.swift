import Foundation

/// Manages SSH key CRUD operations
class SSHKeyManager {
    static let shared = SSHKeyManager()
    
    let sshDirectoryPath: String = NSHomeDirectory() + "/.ssh"

    // Files to skip when scanning for keys
    private let excludedFiles: Set<String> = [
        "config", "known_hosts", "known_hosts.old", "authorized_keys",
        "environment", "rc", "config.d"
    ]

    // MARK: - Scan Keys

    /// Scan ~/.ssh/ for all SSH key pairs
    func scanKeys() async throws -> [SSHKey] {
        let fm = FileManager.default
        let sshDir = sshDirectoryPath

        guard fm.fileExists(atPath: sshDir) else { return [] }

        let contents = try fm.contentsOfDirectory(atPath: sshDir)

        // Find private keys: files that have a matching .pub but are not .pub themselves
        // and are not in the excluded list
        let pubFiles = Set(contents.filter { $0.hasSuffix(".pub") })
        var privateKeyNames: [String] = []

        for file in contents {
            guard !file.hasPrefix("."),
                  !file.hasSuffix(".pub"),
                  !file.hasSuffix(".bak"),
                  !excludedFiles.contains(file),
                  !file.contains(".backup") else { continue }

            let fullPath = (sshDir as NSString).appendingPathComponent(file)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            if isDir.boolValue { continue }

            // Either has a .pub pair, or looks like a key file (check first line)
            let hasPub = pubFiles.contains(file + ".pub")
            let isKey = hasPub ? true : await isLikelyPrivateKey(at: fullPath)
            if isKey {
                privateKeyNames.append(file)
            }
        }

        var keys: [SSHKey] = []
        for name in privateKeyNames {
            if let key = await loadKeyInfo(name: name) {
                keys.append(key)
            }
        }

        return keys.sorted { $0.modificationDate > $1.modificationDate }
    }

    /// Check if a file looks like a private key
    private func isLikelyPrivateKey(at path: String) async -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return false }
        return content.hasPrefix("-----BEGIN") && content.contains("PRIVATE KEY")
    }

    /// Load detailed info for a single key
    private func loadKeyInfo(name: String) async -> SSHKey? {
        let privatePath = (sshDirectoryPath as NSString).appendingPathComponent(name)
        let publicPath = privatePath + ".pub"

        // Read public key content
        let pubContent: String
        if let data = FileManager.default.contents(atPath: publicPath),
           let content = String(data: data, encoding: .utf8) {
            pubContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            pubContent = ""
        }

        // Detect type from public key
        let type = SSHKeyType.detect(from: pubContent)

        // Extract comment (last component of pub key)
        let comment: String
        let pubParts = pubContent.components(separatedBy: " ")
        if pubParts.count >= 3 {
            comment = pubParts.dropFirst(2).joined(separator: " ")
        } else {
            comment = ""
        }

        // Get fingerprints via ssh-keygen
        let (md5, sha256, bits) = await getFingerprints(publicKeyPath: publicPath)

        // File attributes
        let attrs = try? FileManager.default.attributesOfItem(atPath: privatePath)
        let modDate = (attrs?[.modificationDate] as? Date) ?? Date()
        let perms = FilePermissions.octalPermissions(at: privatePath) ?? "unknown"

        return SSHKey(
            id: privatePath,
            name: name,
            type: type,
            bits: bits,
            fingerprintMD5: md5,
            fingerprintSHA256: sha256,
            publicKeyContent: pubContent,
            comment: comment,
            privateKeyPath: privatePath,
            publicKeyPath: publicPath,
            modificationDate: modDate,
            filePermissions: perms,
            referencedByHosts: []
        )
    }

    /// Get MD5 and SHA256 fingerprints using ssh-keygen
    private func getFingerprints(publicKeyPath: String) async -> (md5: String, sha256: String, bits: Int?) {
        var md5 = ""
        var sha256 = ""
        var bits: Int?

        // MD5 fingerprint
        if let result = try? await Shell.run("ssh-keygen -l -E md5 -f \(publicKeyPath.shellEscaped)"),
           result.succeeded {
            let parts = result.stdout.components(separatedBy: " ")
            if parts.count >= 2 {
                bits = Int(parts[0])
                md5 = parts[1].replacingOccurrences(of: "MD5:", with: "")
            }
        }

        // SHA256 fingerprint
        if let result = try? await Shell.run("ssh-keygen -l -E sha256 -f \(publicKeyPath.shellEscaped)"),
           result.succeeded {
            let parts = result.stdout.components(separatedBy: " ")
            if parts.count >= 2 {
                sha256 = parts[1].replacingOccurrences(of: "SHA256:", with: "")
            }
        }

        return (md5, sha256, bits)
    }

    // MARK: - Generate Key

    struct KeyGenerationParams {
        var type: SSHKeyType = .ed25519
        var name: String = "id_ed25519"
        var comment: String = ""
        var passphrase: String = ""
        var bits: Int = 4096 // only for RSA
        var path: String? // nil = default ~/.ssh/<name>
    }

    /// Generate a new SSH key pair
    func generateKey(params: KeyGenerationParams) async throws -> SSHKey {
        let keyPath = params.path ?? (sshDirectoryPath as NSString).appendingPathComponent(params.name)

        // Check if file already exists
        if FileManager.default.fileExists(atPath: keyPath) {
            throw NSError(domain: "SSHKeyManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "密钥文件已存在: \(keyPath)"])
        }

        // Build command
        var cmd = "ssh-keygen -t \(params.type.sshKeygenType)"
        if params.type == .rsa {
            cmd += " -b \(params.bits)"
        }
        cmd += " -C \(params.comment.shellEscaped)"
        cmd += " -f \(keyPath.shellEscaped)"
        cmd += " -N \(params.passphrase.shellEscaped)"

        let result = try await Shell.run(cmd)
        guard result.succeeded else {
            throw NSError(domain: "SSHKeyManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "密钥生成失败: \(result.stderr)"])
        }

        // Set correct permissions
        try FilePermissions.fixPrivateKey(at: keyPath)

        // Load and return the new key
        guard let key = await loadKeyInfo(name: params.name) else {
            throw NSError(domain: "SSHKeyManager", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "密钥生成成功但无法读取信息"])
        }
        return key
    }

    // MARK: - Delete Key

    /// Delete a key pair by moving to Trash
    func deleteKey(_ key: SSHKey) throws {
        let fm = FileManager.default
        let privateURL = URL(fileURLWithPath: key.privateKeyPath)

        // Move private key to trash
        try fm.trashItem(at: privateURL, resultingItemURL: nil)

        // Move public key to trash if exists
        if key.hasPublicKey {
            let publicURL = URL(fileURLWithPath: key.publicKeyPath)
            try fm.trashItem(at: publicURL, resultingItemURL: nil)
        }
    }

    // MARK: - Rename Key

    /// Rename a key pair (private + public), returns new key info
    func renameKey(_ key: SSHKey, to newName: String) async throws -> SSHKey {
        let fm = FileManager.default
        let newPrivatePath = (sshDirectoryPath as NSString).appendingPathComponent(newName)
        let newPublicPath = newPrivatePath + ".pub"

        guard !fm.fileExists(atPath: newPrivatePath) else {
            throw NSError(domain: "SSHKeyManager", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "目标文件名已存在: \(newName)"])
        }

        try fm.moveItem(atPath: key.privateKeyPath, toPath: newPrivatePath)
        if key.hasPublicKey {
            try fm.moveItem(atPath: key.publicKeyPath, toPath: newPublicPath)
        }

        guard let newKey = await loadKeyInfo(name: newName) else {
            throw NSError(domain: "SSHKeyManager", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "重命名成功但无法读取新密钥信息"])
        }
        return newKey
    }

    /// Check if a key name already exists
    func keyExists(name: String) -> Bool {
        let path = (sshDirectoryPath as NSString).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - String Shell Escaping

extension String {
    var shellEscaped: String {
        "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
