import Foundation

/// Manages ~/.ssh/known_hosts file
class KnownHostsManager {
    static let shared = KnownHostsManager()

    let knownHostsPath = NSHomeDirectory() + "/.ssh/known_hosts"

    struct KnownHostEntry: Identifiable {
        let id: Int  // line number
        let host: String
        let keyType: String
        let keyFingerprint: String
        let rawLine: String
        let lineNumber: Int
    }

    /// Parse known_hosts file
    func loadEntries() -> [KnownHostEntry] {
        guard let content = try? String(contentsOfFile: knownHostsPath, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: "\n")
        var entries: [KnownHostEntry] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.components(separatedBy: " ")
            guard parts.count >= 3 else { continue }

            let host = parts[0]
            let keyType = parts[1]
            // Truncate the key for display
            let keyData = parts[2]
            let fingerprint = String(keyData.prefix(24)) + "..."

            entries.append(KnownHostEntry(
                id: index,
                host: host,
                keyType: keyType,
                keyFingerprint: fingerprint,
                rawLine: line,
                lineNumber: index + 1
            ))
        }

        return entries
    }

    /// Remove specific entries by line numbers
    func removeEntries(lineNumbers: Set<Int>) throws {
        guard let content = try? String(contentsOfFile: knownHostsPath, encoding: .utf8) else {
            throw NSError(domain: "KnownHostsManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法读取 known_hosts"])
        }

        var lines = content.components(separatedBy: "\n")
        // Remove in reverse order to maintain line numbers
        for lineNum in lineNumbers.sorted().reversed() {
            let index = lineNum - 1
            if index >= 0 && index < lines.count {
                lines.remove(at: index)
            }
        }

        let newContent = lines.joined(separator: "\n")
        try newContent.write(toFile: knownHostsPath, atomically: true, encoding: .utf8)
    }

    /// Remove all entries for a specific host
    func removeHost(_ host: String) throws {
        let entries = loadEntries()
        let toRemove = Set(entries.filter {
            $0.host == host || $0.host.contains(host)
        }.map { $0.lineNumber })

        if !toRemove.isEmpty {
            try removeEntries(lineNumbers: toRemove)
        }
    }

    /// Find duplicate entries (same host, different keys)
    func findDuplicates() -> [String: [KnownHostEntry]] {
        let entries = loadEntries()
        var grouped: [String: [KnownHostEntry]] = [:]
        for entry in entries {
            // Normalize host (strip port markers like [host]:port)
            let normalizedHost = entry.host
                .replacingOccurrences(of: "\\[|\\]", with: "", options: .regularExpression)
                .components(separatedBy: ":").first ?? entry.host
            grouped[normalizedHost, default: []].append(entry)
        }
        return grouped.filter { $0.value.count > 1 }
    }

    /// Get total entry count
    var entryCount: Int {
        loadEntries().count
    }
}
