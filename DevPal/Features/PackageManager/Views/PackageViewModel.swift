import SwiftUI

@MainActor
class PackageViewModel: ObservableObject {
    @Published var managers: [PackageManagerInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var searchText = ""
    @Published var selectedManagerId: String?
    @Published var sortOrder: PackageSortOrder = .name
    @Published var sortAscending = true
    @Published var showCaskOnly = false      // Homebrew cask filter
    @Published var showFormulaOnly = false   // Homebrew formula filter
    @Published var showOutdatedOnly = false
    @Published var isCheckingOutdated = false
    @Published var selectedPackage: InstalledPackage?
    @Published var packageDetail: PackageDetail?
    @Published var isLoadingDetail = false
    @Published var showUninstallConfirm = false
    @Published var packageToUninstall: InstalledPackage?
    @Published var isUpgrading = false
    @Published var showInstallSheet = false
    @Published var installSearchText = ""
    @Published var installSearchResults: [PackageSearchResult] = []
    @Published var isSearching = false
    @Published var isInstalling = false
    @Published var installAsCask = false
    @Published var uninstalledManagers: [PackageManagerDefinition] = []
    @Published var isInstallingManager = false
    @Published var showUninstallManagerConfirm = false
    @Published var managerToUninstall: PackageManagerDefinition?

    private let service = PackageManagerService.shared

    init() {
        Task { await refresh() }
    }

    var selectedManager: PackageManagerInfo? {
        guard let id = selectedManagerId else { return managers.first }
        return managers.first { $0.id == id }
    }

    var selectedDefinition: PackageManagerDefinition? {
        guard let manager = selectedManager else { return nil }
        return PackageManagerDefinition(rawValue: manager.id)
    }

    var filteredPackages: [InstalledPackage] {
        guard let manager = selectedManager else { return [] }
        var result = manager.packages

        // Brew cask/formula filter
        if manager.id == "brew" {
            if showCaskOnly { result = result.filter { $0.isCask } }
            else if showFormulaOnly { result = result.filter { !$0.isCask } }
        }

        // Outdated filter
        if showOutdatedOnly {
            let outdatedNames = Set(manager.outdatedPackages.map { $0.name })
            result = result.filter { outdatedNames.contains($0.name) }
        }

        // Search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.version?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Sort
        result.sort { a, b in
            let cmp: Bool
            switch sortOrder {
            case .name:
                cmp = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .version:
                cmp = (a.version ?? "") < (b.version ?? "")
            }
            return sortAscending ? cmp : !cmp
        }

        return result
    }

    var totalPackageCount: Int {
        managers.reduce(0) { $0 + $1.packages.count }
    }

    /// Get outdated info for a specific package if available
    func outdatedInfo(for packageName: String) -> OutdatedPackage? {
        selectedManager?.outdatedPackages.first { $0.name == packageName }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        managers = await service.detectManagers()
        uninstalledManagers = service.detectUninstalledManagers(installed: managers)

        if managers.isEmpty {
            errorMessage = "未检测到任何包管理器"
            return
        }

        if selectedManagerId == nil {
            selectedManagerId = managers.first?.id
        }

        successMessage = "检测到 \(managers.count) 个包管理器"

        // Lazy load: only load the selected manager
        if let id = selectedManagerId {
            await loadManagerIfNeeded(id)
        }
    }

    /// Lazy load packages for a manager (only if not yet loaded)
    func loadManagerIfNeeded(_ managerId: String) async {
        guard let idx = managers.firstIndex(where: { $0.id == managerId }),
              !managers[idx].hasLoaded,
              !managers[idx].isLoading,
              let def = PackageManagerDefinition(rawValue: managerId) else { return }

        managers[idx].isLoading = true
        defer { managers[idx].isLoading = false }

        do {
            managers[idx].packages = try await service.listPackages(for: def)
            managers[idx].diskUsage = await service.diskUsage(for: def)
            managers[idx].hasLoaded = true
        } catch {
            managers[idx].error = "加载失败: \(error.localizedDescription)"
        }
    }

    func refreshManager(_ managerId: String) async {
        guard let idx = managers.firstIndex(where: { $0.id == managerId }),
              let def = PackageManagerDefinition(rawValue: managerId) else { return }

        managers[idx].isLoading = true
        managers[idx].error = nil
        defer { managers[idx].isLoading = false }

        do {
            managers[idx].packages = try await service.listPackages(for: def)
            managers[idx].diskUsage = await service.diskUsage(for: def)
            managers[idx].hasLoaded = true
        } catch {
            managers[idx].error = "加载失败: \(error.localizedDescription)"
        }
    }

    /// Check outdated for current manager (manual trigger)
    func checkOutdated() async {
        guard let manager = selectedManager,
              let def = PackageManagerDefinition(rawValue: manager.id) else { return }
        guard def.outdatedCommand != nil else {
            errorMessage = "\(manager.name) 不支持更新检测"
            return
        }

        isCheckingOutdated = true
        defer { isCheckingOutdated = false }

        let outdated = await service.checkOutdated(for: def)
        if let idx = managers.firstIndex(where: { $0.id == manager.id }) {
            managers[idx].outdatedPackages = outdated
        }

        if outdated.isEmpty {
            successMessage = "\(manager.name) 所有包均为最新版本"
        } else {
            successMessage = "\(manager.name) 有 \(outdated.count) 个包可更新"
        }
    }

    /// Check outdated for all managers (manual trigger)
    func checkAllOutdated() async {
        isCheckingOutdated = true
        defer { isCheckingOutdated = false }

        await withTaskGroup(of: (String, [OutdatedPackage]).self) { group in
            for manager in managers {
                guard let def = PackageManagerDefinition(rawValue: manager.id),
                      def.outdatedCommand != nil else { continue }
                group.addTask {
                    let outdated = await self.service.checkOutdated(for: def)
                    return (manager.id, outdated)
                }
            }

            for await (id, outdated) in group {
                if let idx = managers.firstIndex(where: { $0.id == id }) {
                    managers[idx].outdatedPackages = outdated
                }
            }
        }

        let total = managers.reduce(0) { $0 + $1.outdatedPackages.count }
        if total == 0 {
            successMessage = "所有包均为最新版本"
        } else {
            successMessage = "共 \(total) 个包可更新"
        }
    }

    func loadPackageDetail(_ pkg: InstalledPackage) async {
        guard let def = selectedDefinition else { return }
        selectedPackage = pkg
        isLoadingDetail = true
        packageDetail = await service.packageInfo(for: pkg.name, manager: def, installedVersion: pkg.version)
        isLoadingDetail = false
    }

    func clearDetail() {
        selectedPackage = nil
        packageDetail = nil
    }

    func confirmUninstall(_ pkg: InstalledPackage) {
        packageToUninstall = pkg
        showUninstallConfirm = true
    }

    func executeUninstall() async {
        guard let pkg = packageToUninstall,
              let def = selectedDefinition else { return }

        do {
            _ = try await service.uninstall(packageName: pkg.name, manager: def)
            successMessage = "已卸载 \(pkg.name)"
            // Refresh the current manager
            if let id = selectedManagerId {
                await refreshManager(id)
            }
        } catch {
            errorMessage = "卸载失败: \(error.localizedDescription)"
        }
        packageToUninstall = nil
    }

    /// Check outdated for a single selected package
    func checkSinglePackageOutdated() async {
        guard let pkg = selectedPackage,
              let manager = selectedManager,
              let def = PackageManagerDefinition(rawValue: manager.id),
              def.outdatedCommand != nil else {
            errorMessage = "该包管理器不支持更新检测"
            return
        }

        isCheckingOutdated = true
        defer { isCheckingOutdated = false }

        let (result, allOutdated) = await service.checkSinglePackageOutdated(packageName: pkg.name, for: def)

        if let idx = managers.firstIndex(where: { $0.id == manager.id }) {
            if let allOutdated {
                // Fallback path: full check was done, update all outdated
                managers[idx].outdatedPackages = allOutdated
            } else if let info = result {
                // Single check: just add/update this package
                if !managers[idx].outdatedPackages.contains(where: { $0.name == pkg.name }) {
                    managers[idx].outdatedPackages.append(info)
                }
            } else {
                // No update available: remove from outdated
                managers[idx].outdatedPackages.removeAll { $0.name == pkg.name }
            }
        }

        if let info = result {
            successMessage = "\(pkg.name) 可更新: \(info.currentVersion) → \(info.latestVersion)"
        } else {
            successMessage = "\(pkg.name) 已是最新版本"
        }
    }

    /// Upgrade selected package
    func upgradeSelectedPackage() async {
        guard let pkg = selectedPackage,
              let def = selectedDefinition else { return }

        isUpgrading = true
        defer { isUpgrading = false }

        do {
            _ = try await service.upgradePackage(pkg.name, manager: def)
            successMessage = "已更新 \(pkg.name)"
            // Remove from outdated list
            if let managerIdx = managers.firstIndex(where: { $0.id == def.rawValue }) {
                managers[managerIdx].outdatedPackages.removeAll { $0.name == pkg.name }
            }
            // Refresh packages to get new version
            if let id = selectedManagerId {
                await refreshManager(id)
            }
            // Reload detail
            await loadPackageDetail(pkg)
        } catch {
            errorMessage = "更新失败: \(error.localizedDescription)"
        }
    }

    func runHealthCheck() async {
        guard let def = selectedDefinition,
              let idx = managers.firstIndex(where: { $0.id == def.rawValue }) else { return }

        if let report = await service.healthCheck(for: def) {
            managers[idx].healthReport = report
        } else {
            errorMessage = "\(managers[idx].name) 不支持健康检查"
        }
    }

    func exportList() {
        guard let manager = selectedManager else { return }
        let text = service.exportPackageList(manager)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        successMessage = "已复制 \(manager.name) 包列表到剪贴板（\(manager.packages.count) 个包）"
    }

    func exportListToFile() {
        guard let manager = selectedManager else { return }
        let text = service.exportPackageList(manager)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(manager.command)-packages.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                successMessage = "已导出到 \(url.lastPathComponent)"
            } catch {
                errorMessage = "导出失败: \(error.localizedDescription)"
            }
        }
    }

    func copyPackageInfo(_ pkg: InstalledPackage) {
        let text = pkg.version != nil ? "\(pkg.name)@\(pkg.version!)" : pkg.name
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        successMessage = "已复制 \(text)"
    }

    // MARK: - Install

    func openInstallSheet() {
        installSearchText = ""
        installSearchResults = []
        installAsCask = false
        showInstallSheet = true
    }

    func searchPackages() async {
        let query = installSearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let def = selectedDefinition else { return }

        isSearching = true
        defer { isSearching = false }

        if def.searchCommandPrefix != nil {
            installSearchResults = await service.searchPackages(query: query, manager: def)
        } else {
            // No search support — treat query as exact package name
            installSearchResults = [PackageSearchResult(name: query)]
        }
    }

    func installPackage(_ name: String) async {
        guard let def = selectedDefinition else { return }

        isInstalling = true
        defer { isInstalling = false }

        do {
            _ = try await service.installPackage(name, manager: def, isCask: installAsCask)
            successMessage = "已安装 \(name)"
            showInstallSheet = false
            // Refresh to show the new package
            if let id = selectedManagerId {
                await refreshManager(id)
            }
        } catch {
            errorMessage = "安装失败: \(error.localizedDescription)"
        }
    }

    func installDirectInput() async {
        let name = installSearchText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await installPackage(name)
    }

    // MARK: - Manager Install / Uninstall

    func installManager(_ def: PackageManagerDefinition) async {
        isInstallingManager = true
        defer { isInstallingManager = false }

        do {
            _ = try await service.installManager(def)
            successMessage = "已安装 \(def.displayName)"
            await refresh()
        } catch {
            errorMessage = "安装 \(def.displayName) 失败: \(error.localizedDescription)"
        }
    }

    func confirmUninstallManager(_ def: PackageManagerDefinition) {
        managerToUninstall = def
        showUninstallManagerConfirm = true
    }

    func executeUninstallManager() async {
        guard let def = managerToUninstall else { return }

        isInstallingManager = true
        defer { isInstallingManager = false }

        do {
            _ = try await service.uninstallManager(def)
            successMessage = "已卸载 \(def.displayName)"
            if selectedManagerId == def.rawValue {
                selectedManagerId = nil
            }
            await refresh()
        } catch {
            errorMessage = "卸载 \(def.displayName) 失败: \(error.localizedDescription)"
        }
        managerToUninstall = nil
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
