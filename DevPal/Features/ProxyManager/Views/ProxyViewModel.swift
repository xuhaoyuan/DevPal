import SwiftUI
import Combine

@MainActor
class ProxyViewModel: ObservableObject {
    @Published var services: [NetworkService] = []
    @Published var selectedService: String = ""
    @Published var proxyStatuses: [ProxyStatus] = []
    @Published var diagnosisItems: [DiagnosisItem] = []
    @Published var isLoading = false
    @Published var isDisabling = false
    @Published var isDiagnosing = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var showUnreachableWarning = false

    init() {
        Task { await initialize() }
    }

    // MARK: - Initialize

    func initialize() async {
        isLoading = true
        defer { isLoading = false }

        await loadNetworkServices()
        if !selectedService.isEmpty {
            await refreshProxyStatus()
        }
    }

    // MARK: - Network Services

    func loadNetworkServices() async {
        // Get all network services
        guard let result = try? await Shell.run("networksetup -listallnetworkservices"),
              result.succeeded else { return }

        let lines = result.stdout.components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.contains("asterisk") }

        // Detect active interface
        let activeInterface = await detectActiveInterface()

        services = lines.map { name in
            NetworkService(name: name, isActive: name == activeInterface)
        }

        // Select the active one, or first available
        if let active = services.first(where: { $0.isActive }) {
            selectedService = active.name
        } else if let first = services.first {
            selectedService = first.name
        }
    }

    private func detectActiveInterface() async -> String? {
        // Get the active network interface name (e.g. en0)
        guard let routeResult = try? await Shell.run("route -n get default 2>/dev/null | grep interface | awk '{print $2}'"),
              routeResult.succeeded else { return nil }

        let iface = routeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !iface.isEmpty else { return nil }

        // Map hardware interface (en0) to service name (Wi-Fi)
        guard let mapResult = try? await Shell.run("networksetup -listallhardwareports"),
              mapResult.succeeded else { return nil }

        let lines = mapResult.stdout.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.contains("Device: \(iface)"), i > 0 {
                let nameLine = lines[i - 1]
                if let colonRange = nameLine.range(of: "Hardware Port: ") {
                    return String(nameLine[colonRange.upperBound...])
                }
            }
        }

        return nil
    }

    // MARK: - Read Proxy Status

    func refreshProxyStatus() async {
        guard !selectedService.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let svc = selectedService.shellEscaped

        async let httpStatus = readWebProxy(service: svc)
        async let httpsStatus = readSecureWebProxy(service: svc)
        async let socksStatus = readSOCKSProxy(service: svc)
        async let pacStatus = readAutoProxy(service: svc)
        async let discoveryStatus = readProxyAutoDiscovery(service: svc)

        proxyStatuses = await [httpStatus, httpsStatus, socksStatus, pacStatus, discoveryStatus]

        // Check reachability for enabled local proxies
        await checkProxyReachability()

        // Determine warning
        let hasUnreachable = proxyStatuses.contains { $0.enabled && $0.isLocalProxy && $0.reachable == false }
        showUnreachableWarning = hasUnreachable
    }

    private func readWebProxy(service: String) async -> ProxyStatus {
        guard let result = try? await Shell.run("networksetup -getwebproxy \(service)"),
              result.succeeded else {
            return ProxyStatus(type: .http, enabled: false, server: "", port: 0, pacURL: "", reachable: nil)
        }
        return parseProxyOutput(result.stdout, type: .http)
    }

    private func readSecureWebProxy(service: String) async -> ProxyStatus {
        guard let result = try? await Shell.run("networksetup -getsecurewebproxy \(service)"),
              result.succeeded else {
            return ProxyStatus(type: .https, enabled: false, server: "", port: 0, pacURL: "", reachable: nil)
        }
        return parseProxyOutput(result.stdout, type: .https)
    }

    private func readSOCKSProxy(service: String) async -> ProxyStatus {
        guard let result = try? await Shell.run("networksetup -getsocksfirewallproxy \(service)"),
              result.succeeded else {
            return ProxyStatus(type: .socks, enabled: false, server: "", port: 0, pacURL: "", reachable: nil)
        }
        return parseProxyOutput(result.stdout, type: .socks)
    }

    private func readAutoProxy(service: String) async -> ProxyStatus {
        guard let result = try? await Shell.run("networksetup -getautoproxyurl \(service)"),
              result.succeeded else {
            return ProxyStatus(type: .autoPAC, enabled: false, server: "", port: 0, pacURL: "", reachable: nil)
        }
        let lines = result.stdout.components(separatedBy: "\n")
        var enabled = false
        var url = ""
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "enabled": enabled = parts[1].lowercased() == "yes"
            case "url": url = parts[1]
            default: break
            }
        }
        return ProxyStatus(type: .autoPAC, enabled: enabled, server: "", port: 0, pacURL: url, reachable: nil)
    }

    private func readProxyAutoDiscovery(service: String) async -> ProxyStatus {
        guard let result = try? await Shell.run("networksetup -getproxyautodiscovery \(service)"),
              result.succeeded else {
            return ProxyStatus(type: .autoDiscovery, enabled: false, server: "", port: 0, pacURL: "", reachable: nil)
        }
        let enabled = result.stdout.lowercased().contains("on")
        return ProxyStatus(type: .autoDiscovery, enabled: enabled, server: "", port: 0, pacURL: "", reachable: nil)
    }

    private func parseProxyOutput(_ output: String, type: ProxyType) -> ProxyStatus {
        let lines = output.components(separatedBy: "\n")
        var enabled = false
        var server = ""
        var port = 0
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "enabled": enabled = parts[1].lowercased() == "yes"
            case "server": server = parts[1]
            case "port": port = Int(parts[1]) ?? 0
            default: break
            }
        }
        return ProxyStatus(type: type, enabled: enabled, server: server, port: port, pacURL: "", reachable: nil)
    }

    // MARK: - Reachability Check

    private func checkProxyReachability() async {
        for i in proxyStatuses.indices {
            let status = proxyStatuses[i]
            guard status.enabled, status.isLocalProxy, status.port > 0 else { continue }

            // Quick TCP check
            let result = try? await Shell.run(
                "nc -z -w 1 \(status.server) \(status.port) 2>/dev/null && echo OK || echo FAIL",
                timeout: 3
            )
            proxyStatuses[i].reachable = result?.stdout.contains("OK") ?? false
        }
    }

    // MARK: - Disable All Proxies

    func disableAllProxies() async {
        guard !selectedService.isEmpty else { return }
        isDisabling = true
        defer { isDisabling = false }

        let svc = selectedService.shellEscaped
        let commands = [
            "networksetup -setwebproxystate \(svc) off",
            "networksetup -setsecurewebproxystate \(svc) off",
            "networksetup -setsocksfirewallproxystate \(svc) off",
            "networksetup -setautoproxystate \(svc) off",
            "networksetup -setproxyautodiscovery \(svc) off",
        ]

        var allSucceeded = true
        for cmd in commands {
            if let result = try? await Shell.run(cmd) {
                if !result.succeeded {
                    allSucceeded = false
                    errorMessage = "部分操作失败: \(result.stderr)"
                }
            }
        }

        await refreshProxyStatus()

        if allSucceeded {
            successMessage = "所有代理已关闭"
        }
    }

    /// Reset: disable all + clear server/port values
    func resetToDefault() async {
        guard !selectedService.isEmpty else { return }
        isDisabling = true
        defer { isDisabling = false }

        let svc = selectedService.shellEscaped
        let commands = [
            "networksetup -setwebproxy \(svc) '' 0 && networksetup -setwebproxystate \(svc) off",
            "networksetup -setsecurewebproxy \(svc) '' 0 && networksetup -setsecurewebproxystate \(svc) off",
            "networksetup -setsocksfirewallproxy \(svc) '' 0 && networksetup -setsocksfirewallproxystate \(svc) off",
            "networksetup -setautoproxyurl \(svc) '' && networksetup -setautoproxystate \(svc) off",
            "networksetup -setproxyautodiscovery \(svc) off",
        ]

        for cmd in commands {
            _ = try? await Shell.run(cmd)
        }

        await refreshProxyStatus()
        successMessage = "代理已恢复默认（全部关闭并清除配置）"
    }

    // MARK: - Network Diagnosis

    func runDiagnosis() async {
        isDiagnosing = true
        defer { isDiagnosing = false }

        diagnosisItems = [
            DiagnosisItem(label: "DNS 解析", status: .checking),
            DiagnosisItem(label: "国内连通 (baidu.com)", status: .pending),
            DiagnosisItem(label: "国外连通 (google.com)", status: .pending),
        ]

        // DNS
        let dnsStart = Date()
        let dnsResult = try? await Shell.run("nslookup www.apple.com 2>/dev/null | head -5", timeout: 5)
        let dnsMs = Int(Date().timeIntervalSince(dnsStart) * 1000)
        diagnosisItems[0].status = (dnsResult?.succeeded ?? false) ? .success : .failed
        diagnosisItems[0].latency = "\(dnsMs)ms"

        // Domestic
        diagnosisItems[1].status = .checking
        let cnStart = Date()
        let cnResult = try? await Shell.run(
            "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 https://www.baidu.com",
            timeout: 8
        )
        let cnMs = Int(Date().timeIntervalSince(cnStart) * 1000)
        let cnCode = cnResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        diagnosisItems[1].status = cnCode.hasPrefix("2") || cnCode.hasPrefix("3") ? .success : .failed
        diagnosisItems[1].latency = "\(cnMs)ms"

        // International
        diagnosisItems[2].status = .checking
        let intlStart = Date()
        let intlResult = try? await Shell.run(
            "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 https://www.google.com",
            timeout: 8
        )
        let intlMs = Int(Date().timeIntervalSince(intlStart) * 1000)
        let intlCode = intlResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        diagnosisItems[2].status = intlCode.hasPrefix("2") || intlCode.hasPrefix("3") ? .success : .failed
        diagnosisItems[2].latency = "\(intlMs)ms"
    }

    // MARK: - Helpers

    var hasAnyProxyEnabled: Bool {
        proxyStatuses.contains { $0.enabled }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
