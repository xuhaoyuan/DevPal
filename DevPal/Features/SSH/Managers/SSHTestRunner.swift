import Foundation

/// Runs SSH connection tests
class SSHTestRunner {
    static let shared = SSHTestRunner()

    /// Test connection to a specific host
    func testConnection(host: String, user: String = "git") async -> ConnectionTestResult {
        let cmd = "ssh -T -o ConnectTimeout=5 -o StrictHostKeyChecking=no \(user)@\(host) 2>&1"
        do {
            let result = try await Shell.run(cmd, timeout: 10)
            let combined = result.stdout + " " + result.stderr

            // Many Git hosts return exit code 1 with a welcome message
            if combined.lowercased().contains("welcome") ||
               combined.lowercased().contains("successfully authenticated") ||
               combined.lowercased().contains("hi ") ||
               combined.contains("You've successfully authenticated") {
                return ConnectionTestResult(host: host, status: .success(combined.trimmingCharacters(in: .whitespacesAndNewlines)))
            }

            if result.succeeded {
                return ConnectionTestResult(host: host, status: .success(combined))
            }

            return ConnectionTestResult(host: host, status: .failed(combined))
        } catch Shell.ShellError.timeout {
            return ConnectionTestResult(host: host, status: .timeout)
        } catch {
            return ConnectionTestResult(host: host, status: .failed(error.localizedDescription))
        }
    }

    /// Test connection using a Host alias from config
    func testHostConfig(_ config: SSHHostConfig) async -> ConnectionTestResult {
        let host = config.host
        let targetHost = config.hostName.isEmpty ? config.host : config.hostName
        let user = config.user.isEmpty ? "git" : config.user
        let port = config.port ?? 22

        let cmd = "ssh -T -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p \(port) \(user)@\(targetHost) 2>&1"
        do {
            let result = try await Shell.run(cmd, timeout: 10)
            let combined = result.stdout + " " + result.stderr

            if combined.lowercased().contains("welcome") ||
               combined.lowercased().contains("successfully authenticated") ||
               combined.lowercased().contains("hi ") ||
               combined.contains("You've successfully authenticated") {
                return ConnectionTestResult(host: host, status: .success(combined.trimmingCharacters(in: .whitespacesAndNewlines)))
            }

            if result.succeeded {
                return ConnectionTestResult(host: host, status: .success(combined))
            }

            return ConnectionTestResult(host: host, status: .failed(combined))
        } catch Shell.ShellError.timeout {
            return ConnectionTestResult(host: host, status: .timeout)
        } catch {
            return ConnectionTestResult(host: host, status: .failed(error.localizedDescription))
        }
    }

    /// Run verbose diagnostic on a host
    func diagnose(host: String, user: String = "git", port: Int = 22) async -> String {
        let cmd = "ssh -vvv -T -o ConnectTimeout=10 -p \(port) \(user)@\(host) 2>&1"
        do {
            let result = try await Shell.run(cmd, timeout: 15)
            return result.stdout + "\n" + result.stderr
        } catch {
            return "诊断失败: \(error.localizedDescription)"
        }
    }

    /// Test all configs concurrently
    func testAll(configs: [SSHHostConfig]) async -> [ConnectionTestResult] {
        await withTaskGroup(of: ConnectionTestResult.self) { group in
            for config in configs where !config.isGlobal {
                group.addTask {
                    await self.testHostConfig(config)
                }
            }
            var results: [ConnectionTestResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
}
