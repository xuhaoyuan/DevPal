import SwiftUI
import Combine

/// Central ViewModel for SSH feature
@MainActor
class SSHViewModel: ObservableObject {
    // MARK: - Published State

    @Published var keys: [SSHKey] = []
    @Published var configs: [SSHHostConfig] = []
    @Published var testResults: [String: ConnectionTestResult] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // Permission warnings
    @Published var sshDirPermissionOK = true
    @Published var badPermissionKeys: [SSHKey] = []

    // Key count & config count for status bar
    var keyCount: Int { keys.count }
    var configCount: Int { configs.count }

    private let keyManager = SSHKeyManager.shared
    private let configManager = SSHConfigManager.shared
    private let testRunner = SSHTestRunner.shared

    // MARK: - Init

    init() {
        Task { await refresh() }
    }

    // MARK: - Refresh All

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load keys
            var loadedKeys = try await keyManager.scanKeys()

            // Load configs
            let loadedConfigs = try configManager.loadConfigs()
            configs = loadedConfigs

            // Cross-reference: mark which hosts reference each key
            for i in loadedKeys.indices {
                let keyPath = loadedKeys[i].privateKeyPath
                let tilePath = keyPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                loadedKeys[i].referencedByHosts = loadedConfigs.filter {
                    $0.identityFile == keyPath || $0.identityFile == tilePath
                }.map { $0.host }
            }
            keys = loadedKeys

            // Check permissions
            checkPermissions()
        } catch {
            errorMessage = "加载失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Key Operations

    func generateKey(params: SSHKeyManager.KeyGenerationParams) async -> SSHKey? {
        do {
            let key = try await keyManager.generateKey(params: params)
            await refresh()
            successMessage = "密钥 \(key.name) 生成成功"
            return key
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteKey(_ key: SSHKey, cleanupConfig: Bool = false) async {
        do {
            if cleanupConfig {
                for host in key.referencedByHosts {
                    if let config = configs.first(where: { $0.host == host }) {
                        try configManager.removeConfig(id: config.id)
                    }
                }
            }
            try keyManager.deleteKey(key)
            await refresh()
            successMessage = "密钥 \(key.name) 已移到废纸篓"
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
        }
    }

    func renameKey(_ key: SSHKey, to newName: String) async {
        do {
            let oldPath = key.privateKeyPath
            let newKey = try await keyManager.renameKey(key, to: newName)
            try configManager.updateKeyReferences(oldPath: oldPath, newPath: newKey.privateKeyPath)
            await refresh()
            successMessage = "密钥已重命名为 \(newName)"
        } catch {
            errorMessage = "重命名失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Config Operations

    func addConfig(_ config: SSHHostConfig) async {
        do {
            try configManager.addConfig(config)
            await refresh()
            successMessage = "Host \(config.host) 已添加"
        } catch {
            errorMessage = "添加失败: \(error.localizedDescription)"
        }
    }

    func updateConfig(_ config: SSHHostConfig) async {
        do {
            try configManager.updateConfig(config)
            await refresh()
            successMessage = "Host \(config.host) 已更新"
        } catch {
            errorMessage = "更新失败: \(error.localizedDescription)"
        }
    }

    func removeConfig(_ config: SSHHostConfig) async {
        do {
            try configManager.removeConfig(id: config.id)
            await refresh()
            successMessage = "Host \(config.host) 已删除"
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Connection Tests

    func testConnection(for config: SSHHostConfig) async {
        testResults[config.host] = ConnectionTestResult(host: config.host, status: .testing)
        let result = await testRunner.testHostConfig(config)
        testResults[config.host] = result
    }

    func testAllConnections() async {
        for config in configs where !config.isGlobal {
            testResults[config.host] = ConnectionTestResult(host: config.host, status: .testing)
        }
        let results = await testRunner.testAll(configs: configs)
        for result in results {
            testResults[result.host] = result
        }
    }

    // MARK: - Permissions

    func checkPermissions() {
        if let dirInfo = FilePermissions.checkSSHDirectory() {
            sshDirPermissionOK = dirInfo.isCorrect
        }
        badPermissionKeys = keys.filter { !$0.isPermissionCorrect }
    }

    func fixAllPermissions() async {
        do {
            try FilePermissions.fixSSHDirectory()
            for key in badPermissionKeys {
                try FilePermissions.fixPrivateKey(at: key.privateKeyPath)
            }
            await refresh()
            successMessage = "权限已全部修复"
        } catch {
            errorMessage = "权限修复失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    /// List available private keys for IdentityFile picker
    func availablePrivateKeys() -> [(name: String, path: String, type: SSHKeyType)] {
        keys.map { ($0.name, $0.privateKeyPath, $0.type) }
    }
}
