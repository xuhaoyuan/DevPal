import Foundation

/// Parses and serializes ~/.ssh/config with full format preservation
class SSHConfigParser {

    /// A raw block in the config file — either a Host/Match block or a comment/blank section
    enum ConfigBlock {
        case hostBlock(config: SSHHostConfig, lineRange: Range<Int>)
        case freeLines([String])   // Comments, blank lines, or unrecognized blocks between Host sections
    }

    private(set) var blocks: [ConfigBlock] = []
    private var rawContent: String = ""

    // MARK: - Parse

    /// Parse a config file from raw text
    func parse(_ content: String) -> [SSHHostConfig] {
        rawContent = content
        blocks = []

        let lines = content.components(separatedBy: "\n")
        var configs: [SSHHostConfig] = []
        var pendingComments: [String] = []
        var currentHost: SSHHostConfig?
        var currentStartLine = 0
        var currentLines: [String] = []

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // Detect Host line (start of a new block)
            if isHostLine(trimmed) {
                // Save previous block
                if let host = currentHost {
                    let block = ConfigBlock.hostBlock(config: host, lineRange: currentStartLine..<index)
                    blocks.append(block)
                    configs.append(host)
                } else if !pendingComments.isEmpty || !currentLines.isEmpty {
                    blocks.append(.freeLines(pendingComments + currentLines))
                }

                // Start new host block
                let hostValue = extractHostValue(trimmed)
                currentHost = SSHHostConfig(host: hostValue, leadingComments: pendingComments)
                currentHost?.rawLines = [rawLine]
                currentStartLine = index - pendingComments.count
                pendingComments = []
                currentLines = []
                continue
            }

            // If we're inside a Host block, parse the field
            if currentHost != nil {
                if trimmed.isEmpty {
                    // Empty line might end the block or be within it — keep tracking
                    currentHost?.rawLines?.append(rawLine)
                } else if trimmed.hasPrefix("#") {
                    // Comment within host block
                    currentHost?.rawLines?.append(rawLine)
                } else {
                    // Key-value field
                    parseField(trimmed, into: &currentHost!)
                    currentHost?.rawLines?.append(rawLine)
                }
            } else {
                // Outside any host block
                if trimmed.hasPrefix("#") || trimmed.isEmpty {
                    pendingComments.append(rawLine)
                } else {
                    // Stray line (e.g. global directive without Host *)
                    pendingComments.append(rawLine)
                }
            }
        }

        // Save last block
        if let host = currentHost {
            let block = ConfigBlock.hostBlock(config: host, lineRange: currentStartLine..<lines.count)
            blocks.append(block)
            configs.append(host)
        } else if !pendingComments.isEmpty {
            blocks.append(.freeLines(pendingComments))
        }

        return configs
    }

    /// Parse config from file path
    func parseFile(at path: String) throws -> [SSHHostConfig] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return [] }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return parse(content)
    }

    // MARK: - Serialize

    /// Rebuild the full config text, preserving format of unchanged blocks
    func serialize(configs: [SSHHostConfig]) -> String {
        var output: [String] = []

        // Build a lookup for current configs by host name (unique identifier)
        let configMap = Dictionary(uniqueKeysWithValues: configs.map { ($0.host, $0) })

        for block in blocks {
            switch block {
            case .freeLines(let lines):
                output.append(contentsOf: lines)

            case .hostBlock(let original, _):
                if let updated = configMap[original.host] {
                    // Regenerate this host block with updated values
                    output.append(updated.toConfigText())
                }
                // If config was removed (not in configMap), skip it
            }
        }

        // Append any new configs (hosts not in original blocks)
        let existingHosts = Set(blocks.compactMap { block -> String? in
            if case .hostBlock(let config, _) = block { return config.host }
            return nil
        })

        for config in configs where !existingHosts.contains(config.host) {
            if !output.isEmpty && output.last != "" {
                output.append("")
            }
            output.append(config.toConfigText())
        }

        return output.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func isHostLine(_ trimmed: String) -> Bool {
        let lower = trimmed.lowercased()
        return lower.hasPrefix("host ") && !lower.hasPrefix("hostname")
    }

    private func extractHostValue(_ line: String) -> String {
        let parts = line.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        return parts.dropFirst().joined(separator: " ")
    }

    private func parseField(_ line: String, into config: inout SSHHostConfig) {
        // Handle both "Key Value" and "Key=Value" formats
        let cleaned = line.trimmingCharacters(in: .whitespaces)

        // Remove inline comments (but be careful with values that contain #)
        let effectiveLine: String
        if let hashIndex = cleaned.firstIndex(of: "#"),
           hashIndex != cleaned.startIndex,
           cleaned[cleaned.index(before: hashIndex)] == " " {
            effectiveLine = String(cleaned[..<hashIndex]).trimmingCharacters(in: .whitespaces)
        } else {
            effectiveLine = cleaned
        }

        guard !effectiveLine.isEmpty else { return }

        let key: String
        let value: String

        if effectiveLine.contains("=") {
            let parts = effectiveLine.split(separator: "=", maxSplits: 1)
            key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        } else {
            let parts = effectiveLine.split(separator: " ", maxSplits: 1)
            key = String(parts[0])
            value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        }

        switch key.lowercased() {
        case "hostname":
            config.hostName = value
        case "user":
            config.user = value
        case "port":
            config.port = Int(value)
        case "identityfile":
            config.identityFile = value
        case "identitiesonly":
            config.identitiesOnly = value.lowercased() == "yes"
        case "identityagent":
            config.identityAgent = value
        case "preferredauthentications":
            config.preferredAuthentications = value
        case "forwardagent":
            config.forwardAgent = value.lowercased() == "yes"
        case "proxycommand":
            config.proxyCommand = value
        case "proxyjump":
            config.proxyJump = value
        case "serveraliveinterval":
            config.serverAliveInterval = Int(value)
        case "serveralivecountmax":
            config.serverAliveCountMax = Int(value)
        case "stricthostkeychecking":
            config.strictHostKeyChecking = value
        case "compression":
            config.compression = value.lowercased() == "yes"
        case "loglevel":
            config.logLevel = value
        case "addkeystoagent":
            config.addKeysToAgent = value
        case "usekeychain":
            config.useKeychain = value.lowercased() == "yes"
        case "localforward":
            config.localForward = value
        case "remoteforward":
            config.remoteForward = value
        default:
            // Preserve unknown fields
            config.customFields.append((key: key, value: value))
        }
    }
}
