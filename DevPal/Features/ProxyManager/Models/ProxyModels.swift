import Foundation

// MARK: - Proxy Type

enum ProxyType: String, CaseIterable, Identifiable {
    case http = "HTTP 代理"
    case https = "HTTPS 代理"
    case socks = "SOCKS 代理"
    case autoPAC = "自动代理 (PAC)"
    case autoDiscovery = "自动发现"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .http: return "globe"
        case .https: return "lock.shield"
        case .socks: return "network"
        case .autoPAC: return "doc.text"
        case .autoDiscovery: return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Proxy Status

struct ProxyStatus: Identifiable {
    let id = UUID()
    let type: ProxyType
    var enabled: Bool
    var server: String   // empty for PAC/autoDiscovery
    var port: Int         // 0 for PAC/autoDiscovery
    var pacURL: String    // only for autoPAC
    var reachable: Bool?  // nil = not checked, true/false = checked

    var isLocalProxy: Bool {
        enabled && (server == "127.0.0.1" || server == "localhost" || server == "0.0.0.0")
    }

    var displayAddress: String {
        if type == .autoPAC {
            return pacURL.isEmpty ? "-" : pacURL
        }
        if type == .autoDiscovery {
            return ""
        }
        if server.isEmpty { return "-" }
        return "\(server):\(port)"
    }
}

// MARK: - Network Service

struct NetworkService: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var isActive: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: NetworkService, rhs: NetworkService) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - Diagnosis Result

struct DiagnosisItem: Identifiable {
    let id = UUID()
    let label: String
    var status: DiagnosisStatus
    var latency: String? // e.g. "12ms"
}

enum DiagnosisStatus: Equatable {
    case pending
    case checking
    case success
    case failed
}
