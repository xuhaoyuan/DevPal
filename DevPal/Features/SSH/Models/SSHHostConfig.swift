import Foundation

// MARK: - SSH Host Config Model

struct SSHHostConfig: Identifiable, Hashable {
    let id: UUID
    var host: String                         // Host alias (e.g. "codeup-zhw", "*")
    var hostName: String                     // Real hostname/IP
    var user: String                         // Login user, default "git"
    var port: Int?                           // SSH port, nil = default 22
    var identityFile: String                 // Path to private key
    var identitiesOnly: Bool                 // Only use specified key
    var identityAgent: String?               // SSH agent socket path, "none" to disable

    // Advanced fields
    var preferredAuthentications: String?
    var forwardAgent: Bool?
    var proxyCommand: String?
    var proxyJump: String?
    var serverAliveInterval: Int?
    var serverAliveCountMax: Int?
    var strictHostKeyChecking: String?
    var compression: Bool?
    var logLevel: String?
    var addKeysToAgent: String?
    var useKeychain: Bool?
    var localForward: String?
    var remoteForward: String?

    // Custom key-value pairs for unknown/unsupported fields
    var customFields: [(key: String, value: String)]

    // Preserve original formatting
    var leadingComments: [String]            // Comment lines above this Host block
    var rawLines: [String]?                  // Original raw lines for preservation

    var isGlobal: Bool { host == "*" }
    var displayPort: String? { port != nil && port != 22 ? "\(port!)" : nil }

    var identityFileName: String {
        (identityFile as NSString).lastPathComponent
    }

    init(
        id: UUID = UUID(),
        host: String = "",
        hostName: String = "",
        user: String = "git",
        port: Int? = nil,
        identityFile: String = "",
        identitiesOnly: Bool = true,
        identityAgent: String? = nil,
        preferredAuthentications: String? = "publickey",
        forwardAgent: Bool? = nil,
        proxyCommand: String? = nil,
        proxyJump: String? = nil,
        serverAliveInterval: Int? = nil,
        serverAliveCountMax: Int? = nil,
        strictHostKeyChecking: String? = nil,
        compression: Bool? = nil,
        logLevel: String? = nil,
        addKeysToAgent: String? = nil,
        useKeychain: Bool? = nil,
        localForward: String? = nil,
        remoteForward: String? = nil,
        customFields: [(key: String, value: String)] = [],
        leadingComments: [String] = [],
        rawLines: [String]? = nil
    ) {
        self.id = id
        self.host = host
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.identitiesOnly = identitiesOnly
        self.identityAgent = identityAgent
        self.preferredAuthentications = preferredAuthentications
        self.forwardAgent = forwardAgent
        self.proxyCommand = proxyCommand
        self.proxyJump = proxyJump
        self.serverAliveInterval = serverAliveInterval
        self.serverAliveCountMax = serverAliveCountMax
        self.strictHostKeyChecking = strictHostKeyChecking
        self.compression = compression
        self.logLevel = logLevel
        self.addKeysToAgent = addKeysToAgent
        self.useKeychain = useKeychain
        self.localForward = localForward
        self.remoteForward = remoteForward
        self.customFields = customFields
        self.leadingComments = leadingComments
        self.rawLines = rawLines
    }

    /// Generate SSH config text block for this host
    func toConfigText() -> String {
        var lines: [String] = []

        for comment in leadingComments {
            lines.append(comment)
        }

        lines.append("Host \(host)")
        if !hostName.isEmpty { lines.append("  HostName \(hostName)") }
        if !user.isEmpty { lines.append("  User \(user)") }
        if let port = port, port != 22 { lines.append("  Port \(port)") }
        if let auth = preferredAuthentications { lines.append("  PreferredAuthentications \(auth)") }
        if !identityFile.isEmpty { lines.append("  IdentityFile \(identityFile)") }
        if identitiesOnly { lines.append("  IdentitiesOnly yes") }
        if let ia = identityAgent { lines.append("  IdentityAgent \(ia)") }
        if let fa = forwardAgent { lines.append("  ForwardAgent \(fa ? "yes" : "no")") }
        if let pc = proxyCommand { lines.append("  ProxyCommand \(pc)") }
        if let pj = proxyJump { lines.append("  ProxyJump \(pj)") }
        if let sai = serverAliveInterval { lines.append("  ServerAliveInterval \(sai)") }
        if let sacm = serverAliveCountMax { lines.append("  ServerAliveCountMax \(sacm)") }
        if let shk = strictHostKeyChecking { lines.append("  StrictHostKeyChecking \(shk)") }
        if let comp = compression { lines.append("  Compression \(comp ? "yes" : "no")") }
        if let ll = logLevel { lines.append("  LogLevel \(ll)") }
        if let aka = addKeysToAgent { lines.append("  AddKeysToAgent \(aka)") }
        if let uk = useKeychain { lines.append("  UseKeychain \(uk ? "yes" : "no")") }
        if let lf = localForward { lines.append("  LocalForward \(lf)") }
        if let rf = remoteForward { lines.append("  RemoteForward \(rf)") }
        for field in customFields {
            lines.append("  \(field.key) \(field.value)")
        }

        return lines.joined(separator: "\n")
    }

    static func == (lhs: SSHHostConfig, rhs: SSHHostConfig) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Connection Test Result

enum ConnectionStatus: Equatable {
    case untested
    case testing
    case success(String)    // Welcome message
    case failed(String)     // Error message
    case timeout

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

struct ConnectionTestResult: Identifiable {
    let id: UUID
    let host: String
    let status: ConnectionStatus
    let timestamp: Date

    init(host: String, status: ConnectionStatus) {
        self.id = UUID()
        self.host = host
        self.status = status
        self.timestamp = Date()
    }
}
