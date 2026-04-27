import Foundation

/// Represents a network port being used by a process
struct PortUsage: Identifiable, Hashable {
    let id = UUID()
    let port: Int
    let `protocol`: String      // tcp / udp
    let address: String         // 0.0.0.0, 127.0.0.1, ::1
    let pid: Int32
    let processName: String
    let user: String
    let state: String           // LISTEN, ESTABLISHED, etc.

    var isListening: Bool { state.uppercased() == "LISTEN" }
    var isLocalhost: Bool { address == "127.0.0.1" || address == "::1" || address == "localhost" }
}

/// Wraps `lsof` for port enumeration
enum PortScanner {
    /// Scan all ports in use. If `listenOnly` is true, only LISTEN sockets are returned.
    static func scan(listenOnly: Bool = true) async -> [PortUsage] {
        // -i: network files, -P: numeric ports, -n: numeric addresses, +c0: full process name
        let flag = listenOnly ? "-iTCP -sTCP:LISTEN -iUDP" : "-i"
        let cmd = "lsof -nP +c0 \(flag) 2>/dev/null"

        guard let result = try? await Shell.run(cmd, timeout: 10),
              !result.stdout.isEmpty else {
            return []
        }

        return parse(output: result.stdout, listenOnly: listenOnly)
    }

    /// Kill the process owning a port
    static func kill(pid: Int32, force: Bool = false) async throws {
        let signal = force ? "-9" : "-15"
        let cmd = "kill \(signal) \(pid)"
        let result = try await Shell.run(cmd, timeout: 5)
        if !result.succeeded {
            throw NSError(domain: "PortScanner", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法终止进程 (PID \(pid)): \(result.stderr)"])
        }
    }

    // MARK: - Parsing

    /// lsof output columns (tab-separated by default whitespace):
    /// COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
    private static func parse(output: String, listenOnly: Bool) -> [PortUsage] {
        var results: [PortUsage] = []
        let lines = output.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }

        for line in lines.dropFirst() {  // skip header
            let cols = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard cols.count >= 9 else { continue }

            let command = cols[0]
            guard let pid = Int32(cols[1]) else { continue }
            let user = cols[2]
            let type = cols[4]               // IPv4, IPv6
            let proto = cols[7]              // TCP, UDP
            let nameField = cols[8...].joined(separator: " ")

            // Parse "host:port (STATE)" or "host:port"
            var state = ""
            var addressPort = nameField
            if let parenStart = nameField.range(of: " ("),
               let parenEnd = nameField.range(of: ")", options: .backwards) {
                addressPort = String(nameField[..<parenStart.lowerBound])
                state = String(nameField[parenStart.upperBound..<parenEnd.lowerBound])
            }

            // Skip "->" remote endpoint addresses (only keep listening side)
            guard !addressPort.contains("->") else { continue }

            // Parse "host:port"
            guard let lastColon = addressPort.lastIndex(of: ":") else { continue }
            let address = String(addressPort[..<lastColon])
            let portStr = String(addressPort[addressPort.index(after: lastColon)...])
            guard let port = Int(portStr) else { continue }

            let cleanAddress = address.replacingOccurrences(of: "*", with: "0.0.0.0")
                                       .replacingOccurrences(of: "[", with: "")
                                       .replacingOccurrences(of: "]", with: "")

            let usage = PortUsage(
                port: port,
                protocol: proto.lowercased(),
                address: cleanAddress,
                pid: pid,
                processName: command,
                user: user,
                state: state.isEmpty ? (proto.uppercased() == "UDP" ? "UDP" : "LISTEN") : state
            )

            if listenOnly && !usage.isListening && proto.uppercased() != "UDP" {
                continue
            }

            results.append(usage)
            _ = type  // unused
        }

        // Deduplicate by (pid, port, proto)
        var seen = Set<String>()
        return results.filter {
            let key = "\($0.pid)-\($0.port)-\($0.protocol)"
            return seen.insert(key).inserted
        }.sorted { $0.port < $1.port }
    }

    // MARK: - Common Ports Reference

    static let commonPorts: [Int: String] = [
        20: "FTP Data", 21: "FTP Control", 22: "SSH", 23: "Telnet",
        25: "SMTP", 53: "DNS", 80: "HTTP", 110: "POP3",
        143: "IMAP", 443: "HTTPS", 465: "SMTPS", 587: "SMTP Submission",
        993: "IMAPS", 995: "POP3S", 1080: "SOCKS Proxy",
        1433: "SQL Server", 1521: "Oracle", 1883: "MQTT",
        2375: "Docker (insecure)", 2376: "Docker (TLS)",
        2379: "etcd", 2380: "etcd peer",
        3000: "Node/React Dev", 3001: "Node Dev", 3306: "MySQL",
        3307: "MySQL alt", 3389: "RDP",
        4200: "Angular Dev", 4444: "Selenium",
        5000: "Flask/Python", 5001: "Python alt",
        5173: "Vite Dev", 5174: "Vite alt",
        5432: "PostgreSQL", 5433: "PostgreSQL alt",
        5601: "Kibana", 5672: "RabbitMQ", 5984: "CouchDB",
        6000: "X11", 6379: "Redis", 6443: "Kubernetes API",
        7000: "Cassandra", 7001: "WebLogic", 7474: "Neo4j",
        8000: "HTTP alt / Django",
        8080: "HTTP alt / Tomcat", 8081: "HTTP alt 2",
        8086: "InfluxDB", 8088: "Hadoop",
        8443: "HTTPS alt", 8888: "Jupyter",
        9000: "PHP-FPM / SonarQube", 9092: "Kafka",
        9200: "Elasticsearch", 9300: "Elasticsearch nodes",
        9418: "Git", 9999: "通用调试",
        11211: "Memcached", 15672: "RabbitMQ Mgmt",
        27017: "MongoDB", 27018: "MongoDB shard",
        50000: "DB2 / SAP",
    ]
}
