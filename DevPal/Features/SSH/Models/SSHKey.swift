import Foundation

// MARK: - SSH Key Type

enum SSHKeyType: String, CaseIterable, Identifiable, Codable {
    case ed25519 = "ED25519"
    case rsa = "RSA"
    case ecdsa = "ECDSA"
    case dsa = "DSA"
    case unknown = "Unknown"

    var id: String { rawValue }

    var defaultBits: Int? {
        switch self {
        case .rsa: return 4096
        case .ecdsa: return 256
        case .ed25519: return 256
        case .dsa: return 1024
        case .unknown: return nil
        }
    }

    var availableBits: [Int]? {
        switch self {
        case .rsa: return [2048, 3072, 4096]
        case .ecdsa: return [256, 384, 521]
        default: return nil
        }
    }

    var sshKeygenType: String {
        switch self {
        case .ed25519: return "ed25519"
        case .rsa: return "rsa"
        case .ecdsa: return "ecdsa"
        case .dsa: return "dsa"
        case .unknown: return "ed25519"
        }
    }

    /// Detect key type from public key content or ssh-keygen output
    static func detect(from content: String) -> SSHKeyType {
        let lower = content.lowercased()
        if lower.contains("ed25519") { return .ed25519 }
        if lower.contains("ecdsa") { return .ecdsa }
        if lower.contains("dsa") && !lower.contains("ecdsa") { return .dsa }
        if lower.contains("rsa") { return .rsa }
        return .unknown
    }
}

// MARK: - SSH Key Model

struct SSHKey: Identifiable, Hashable {
    let id: String
    let name: String
    let type: SSHKeyType
    let bits: Int?
    let fingerprintMD5: String
    let fingerprintSHA256: String
    let publicKeyContent: String
    let comment: String
    let privateKeyPath: String
    let publicKeyPath: String
    let modificationDate: Date
    let filePermissions: String
    var referencedByHosts: [String]

    var isPermissionCorrect: Bool {
        filePermissions == "600"
    }

    var hasPublicKey: Bool {
        FileManager.default.fileExists(atPath: publicKeyPath)
    }

    var displayFingerprint: String {
        String(fingerprintMD5.prefix(20)) + "..."
    }

    static func == (lhs: SSHKey, rhs: SSHKey) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
