import Foundation

class PackageManagerService {
    static let shared = PackageManagerService()

    /// Detect which package managers are installed
    func detectManagers() async -> [PackageManagerInfo] {
        var results: [PackageManagerInfo] = []

        for def in PackageManagerDefinition.allCases {
            let whichResult = try? await Shell.run("which \(def.command)")
            guard let path = whichResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty, whichResult?.succeeded == true else {
                continue
            }

            let versionResult = try? await Shell.run(def.versionCommand)
            let version = versionResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

            var info = PackageManagerInfo(
                id: def.rawValue,
                name: def.displayName,
                icon: def.icon,
                command: def.command,
                version: version,
                path: path
            )
            info.isLoading = false
            results.append(info)
        }

        return results
    }

    /// Detect which package managers are NOT installed
    func detectUninstalledManagers(installed: [PackageManagerInfo]) -> [PackageManagerDefinition] {
        let installedIds = Set(installed.map { $0.id })
        return PackageManagerDefinition.allCases.filter { !installedIds.contains($0.rawValue) }
    }

    /// Install a package manager
    func installManager(_ definition: PackageManagerDefinition) async throws -> String {
        guard let script = definition.managerInstallScript else {
            throw Shell.ShellError.processError(definition.managerInstallHint ?? "该包管理器不支持自动安装")
        }
        let result = try await Shell.run(script, timeout: 600)
        if result.succeeded {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw Shell.ShellError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Uninstall a package manager
    func uninstallManager(_ definition: PackageManagerDefinition) async throws -> String {
        guard let script = definition.managerUninstallScript else {
            throw Shell.ShellError.processError("该包管理器不支持自动卸载")
        }
        let result = try await Shell.run(script, timeout: 300)
        if result.succeeded {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw Shell.ShellError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// List installed packages for a specific manager
    func listPackages(for definition: PackageManagerDefinition) async throws -> [InstalledPackage] {
        let result = try await Shell.run(definition.listWithVersionsCommand, timeout: 60)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return [] }

        var packages: [InstalledPackage]
        switch definition {
        case .brew:
            packages = parseBrewList(output)
            // Mark cask packages
            if let caskResult = try? await Shell.run("brew list --cask -1 2>/dev/null", timeout: 30) {
                let caskNames = Set(caskResult.stdout.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
                packages = packages.map { pkg in
                    var p = pkg
                    p.isCask = caskNames.contains(pkg.name)
                    return p
                }
            }
        case .npm:
            packages = parseNpmList(output)
        case .pnpm:
            packages = parsePnpmList(output)
        case .yarn:
            packages = parseYarnList(output)
        case .pip3:
            packages = parsePipList(output)
        case .pipx:
            packages = parsePipxList(output)
        case .conda:
            packages = parseCondaList(output)
        case .gem:
            packages = parseGemList(output)
        case .cargo:
            packages = parseCargoList(output)
        case .go:
            packages = parseGoList(output)
        case .composer:
            packages = parseComposerList(output)
        case .pod:
            packages = parsePodList(output)
        }
        return packages
    }

    /// Check outdated for a single package. Returns (single result, full list if fallback was used)
    func checkSinglePackageOutdated(packageName: String, for definition: PackageManagerDefinition) async -> (result: OutdatedPackage?, allOutdated: [OutdatedPackage]?) {
        switch definition {
        case .brew:
            guard let result = try? await Shell.run("brew outdated \(packageName) --verbose 2>/dev/null", timeout: 30) else { return (nil, nil) }
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else { return (nil, nil) }
            return (parseBrewOutdated(output).first { $0.name == packageName }, nil)
        case .npm:
            guard let result = try? await Shell.run("npm outdated -g \(packageName) 2>/dev/null", timeout: 30) else { return (nil, nil) }
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else { return (nil, nil) }
            return (parseNpmOutdated(output).first { $0.name == packageName }, nil)
        default:
            // Fallback: check all, return the full list along with the single result
            let all = await checkOutdated(for: definition)
            return (all.first { $0.name == packageName }, all)
        }
    }

    /// Check for outdated packages
    func checkOutdated(for definition: PackageManagerDefinition) async -> [OutdatedPackage] {
        guard let cmd = definition.outdatedCommand else { return [] }
        guard let result = try? await Shell.run(cmd, timeout: 120) else { return [] }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return [] }

        switch definition {
        case .brew:
            return parseBrewOutdated(output)
        case .npm:
            return parseNpmOutdated(output)
        case .pip3:
            return parsePipOutdated(output)
        case .conda:
            return parseCondaOutdated(output)
        case .gem:
            return parseGemOutdated(output)
        case .composer:
            return parseComposerOutdated(output)
        default:
            return []
        }
    }

    /// Get detailed info about a package
    func packageInfo(for packageName: String, manager: PackageManagerDefinition, installedVersion: String? = nil) async -> PackageDetail? {
        // npm: use `npm view` with specific fields for compact JSON output
        if manager == .npm {
            let versionSuffix = installedVersion.map { "@\($0)" } ?? ""
            let cmd = "npm view \(packageName)\(versionSuffix) name version description homepage license author repository keywords dependencies --json 2>/dev/null"
            guard let result = try? await Shell.run(cmd, timeout: 30) else { return nil }
            let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return parseNpmInfo(raw, name: packageName)
        }

        guard let prefix = manager.infoCommandPrefix else { return nil }
        guard let result = try? await Shell.run("\(prefix) \(packageName) 2>/dev/null", timeout: 30) else { return nil }
        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        switch manager {
        case .brew:
            return parseBrewInfo(raw, name: packageName)
        case .npm:
            return parseNpmInfo(raw, name: packageName)
        case .pip3:
            return parsePipInfo(raw, name: packageName)
        case .gem:
            return parseGemInfo(raw, name: packageName)
        default:
            return PackageDetail(name: packageName, version: nil, description: nil, homepage: nil, license: nil, dependencies: [], installedSize: nil, rawInfo: raw)
        }
    }

    /// Uninstall a package
    func uninstall(packageName: String, manager: PackageManagerDefinition) async throws -> String {
        guard let prefix = manager.uninstallCommandPrefix else {
            throw Shell.ShellError.processError("该包管理器不支持卸载操作")
        }
        let result = try await Shell.run("\(prefix) \(packageName)", timeout: 120)
        if result.succeeded {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw Shell.ShellError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Upgrade a specific package
    func upgradePackage(_ packageName: String, manager: PackageManagerDefinition) async throws -> String {
        guard let prefix = manager.upgradeCommandPrefix else {
            throw Shell.ShellError.processError("该包管理器不支持更新操作")
        }
        let result = try await Shell.run("\(prefix) \(packageName)", timeout: 300)
        if result.succeeded {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw Shell.ShellError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Run health check
    func healthCheck(for definition: PackageManagerDefinition) async -> String? {
        guard let cmd = definition.healthCommand else { return nil }
        guard let result = try? await Shell.run(cmd, timeout: 60) else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Search for packages
    func searchPackages(query: String, manager: PackageManagerDefinition) async -> [PackageSearchResult] {
        guard let prefix = manager.searchCommandPrefix else { return [] }
        guard let result = try? await Shell.run("\(prefix) \(query) 2>/dev/null", timeout: 30) else { return [] }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return [] }

        switch manager {
        case .brew:
            return parseBrewSearch(output)
        case .npm:
            return parseNpmSearch(output)
        case .gem:
            return parseGemSearch(output)
        case .composer:
            return parseComposerSearch(output)
        default:
            return output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .prefix(50)
                .map { PackageSearchResult(name: $0) }
        }
    }

    /// Install a package
    func installPackage(_ packageName: String, manager: PackageManagerDefinition, isCask: Bool = false) async throws -> String {
        guard let prefix = manager.installCommandPrefix else {
            throw Shell.ShellError.processError("该包管理器不支持安装操作")
        }
        let cmd: String
        if manager == .brew && isCask {
            cmd = "brew install --cask \(packageName)"
        } else {
            cmd = "\(prefix) \(packageName)"
        }
        let result = try await Shell.run(cmd, timeout: 300)
        if result.succeeded {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw Shell.ShellError.executionFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Get disk usage
    func diskUsage(for definition: PackageManagerDefinition) async -> String? {
        guard let cmd = definition.diskUsageCommand else { return nil }
        guard let result = try? await Shell.run(cmd, timeout: 30) else { return nil }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    /// Export package list as text
    func exportPackageList(_ manager: PackageManagerInfo) -> String {
        var lines: [String] = []
        lines.append("# \(manager.name) 已安装包列表")
        if let version = manager.version {
            lines.append("# 版本: \(version)")
        }
        lines.append("# 导出时间: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("# 共 \(manager.packages.count) 个包")
        lines.append("")

        for pkg in manager.packages.sorted(by: { $0.name < $1.name }) {
            if let v = pkg.version {
                lines.append("\(pkg.name) \(v)")
            } else {
                lines.append(pkg.name)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Outdated Parsers

    /// brew outdated --verbose → "cmake (3.28.1) < 3.29.0"
    private func parseBrewOutdated(_ output: String) -> [OutdatedPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let pattern = /^(.+?)\s+\((.+?)\)\s+<\s+(.+)$/
            if let match = line.trimmingCharacters(in: .whitespaces).firstMatch(of: pattern) {
                return OutdatedPackage(name: String(match.1), currentVersion: String(match.2), latestVersion: String(match.3))
            }
            return nil
        }
    }

    /// npm outdated -g → table format "Package  Current  Wanted  Latest"
    private func parseNpmOutdated(_ output: String) -> [OutdatedPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: " ").map(String.init)
            // Package Current Wanted Latest Location
            guard parts.count >= 4, parts[0] != "Package" else { return nil }
            return OutdatedPackage(name: parts[0], currentVersion: parts[1], latestVersion: parts[3])
        }
    }

    /// pip3 list --outdated → "package version latest type"
    private func parsePipOutdated(_ output: String) -> [OutdatedPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 3 else { return nil }
            return OutdatedPackage(name: parts[0], currentVersion: parts[1], latestVersion: parts[2])
        }
    }

    /// gem outdated → "name (current < latest)"
    private func parseGemOutdated(_ output: String) -> [OutdatedPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let pattern = /^(.+?)\s+\((.+?)\s+<\s+(.+?)\)$/
            if let match = line.trimmingCharacters(in: .whitespaces).firstMatch(of: pattern) {
                return OutdatedPackage(name: String(match.1), currentVersion: String(match.2), latestVersion: String(match.3))
            }
            return nil
        }
    }

    /// composer outdated → "package current latest description"
    private func parseComposerOutdated(_ output: String) -> [OutdatedPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3)
            guard parts.count >= 3 else { return nil }
            return OutdatedPackage(name: String(parts[0]), currentVersion: String(parts[1]), latestVersion: String(parts[2]))
        }
    }

    // MARK: - Info Parsers

    private func parseBrewInfo(_ raw: String, name: String) -> PackageDetail {
        // brew info --json=v1 <pkg> → JSON array with one element
        guard let data = raw.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let json = jsonArray.first else {
            // Fallback to raw text
            return PackageDetail(name: name, version: nil, description: nil, homepage: nil, license: nil, dependencies: [], installedSize: nil, rawInfo: raw)
        }

        let desc = json["desc"] as? String
        let homepage = json["homepage"] as? String
        let license = json["license"] as? String
        let deps = json["dependencies"] as? [String] ?? []

        var version: String?
        if let versions = json["versions"] as? [String: Any] {
            version = versions["stable"] as? String
        }

        var installedVersion: String?
        var installedSize: String?
        if let installed = json["installed"] as? [[String: Any]], let first = installed.first {
            installedVersion = first["version"] as? String
            if let bytes = first["installed_as_dependency"] as? Bool {
                _ = bytes // Available if needed
            }
        }

        // Build rich rawInfo from JSON
        var infoLines: [String] = []
        let fullName = json["full_name"] as? String ?? name
        infoLines.append("\(fullName) \(installedVersion ?? version ?? "")")
        if let desc = desc { infoLines.append(desc) }
        if let homepage = homepage { infoLines.append("Homepage: \(homepage)") }
        if let license = license { infoLines.append("License: \(license)") }

        if let versions = json["versions"] as? [String: Any] {
            let stable = versions["stable"] as? String ?? "N/A"
            let head = versions["head"] as? String
            infoLines.append("Stable: \(stable)\(head.map { ", HEAD: \($0)" } ?? "")")
        }

        if !deps.isEmpty {
            infoLines.append("Dependencies: \(deps.joined(separator: ", "))")
        }
        if let buildDeps = json["build_dependencies"] as? [String], !buildDeps.isEmpty {
            infoLines.append("Build Dependencies: \(buildDeps.joined(separator: ", "))")
        }

        if let caveats = json["caveats"] as? String, !caveats.isEmpty {
            infoLines.append("Caveats:\n\(caveats)")
        }

        if let installed = json["installed"] as? [[String: Any]] {
            for inst in installed {
                if let v = inst["version"] as? String {
                    let asDep = (inst["installed_as_dependency"] as? Bool == true) ? " (as dependency)" : ""
                    infoLines.append("Installed: \(v)\(asDep)")
                }
            }
        }

        if let linked = json["linked_keg"] as? String {
            infoLines.append("Linked: \(linked)")
        }

        return PackageDetail(name: name, version: installedVersion ?? version, description: desc, homepage: homepage, license: license, dependencies: deps, installedSize: installedSize, rawInfo: infoLines.joined(separator: "\n"))
    }

    private func parseNpmInfo(_ raw: String, name: String) -> PackageDetail {
        // npm info <pkg> --json → full JSON with name, version, description, homepage, license, dependencies, etc.
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PackageDetail(name: name, version: nil, description: nil, homepage: nil, license: nil, dependencies: [], installedSize: nil, rawInfo: raw)
        }

        let version = json["version"] as? String
        let desc = json["description"] as? String
        let homepage = json["homepage"] as? String
        let license = json["license"] as? String

        var deps: [String] = []
        if let dependencies = json["dependencies"] as? [String: String] {
            deps = dependencies.map { "\($0.key)@\($0.value)" }.sorted()
        }

        // Build rich rawInfo from JSON fields
        var infoLines: [String] = []
        infoLines.append("\(name)@\(version ?? "unknown")")
        if let license = license { infoLines.append("License: \(license)") }
        if let desc = desc { infoLines.append("Description: \(desc)") }
        if let homepage = homepage { infoLines.append("Homepage: \(homepage)") }

        if let keywords = json["keywords"] as? [String], !keywords.isEmpty {
            infoLines.append("Keywords: \(keywords.joined(separator: ", "))")
        }
        if let author = json["author"] as? String {
            infoLines.append("Author: \(author)")
        } else if let author = json["author"] as? [String: Any], let authorName = author["name"] as? String {
            let email = author["email"] as? String
            infoLines.append("Author: \(authorName)\(email.map { " <\($0)>" } ?? "")")
        }
        if let repo = json["repository"] as? [String: Any], let repoUrl = repo["url"] as? String {
            infoLines.append("Repository: \(repoUrl)")
        } else if let repo = json["repository"] as? String {
            infoLines.append("Repository: \(repo)")
        }

        if let distTags = json["dist-tags"] as? [String: String] {
            let tags = distTags.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            infoLines.append("Tags: \(tags)")
        }

        if !deps.isEmpty {
            infoLines.append("Dependencies (\(deps.count)): \(deps.prefix(20).joined(separator: ", "))")
            if deps.count > 20 { infoLines.append("  ... and \(deps.count - 20) more") }
        }

        if let maintainers = json["maintainers"] as? [[String: String]] {
            let names = maintainers.compactMap { $0["name"] ?? $0["email"] }
            if !names.isEmpty { infoLines.append("Maintainers: \(names.joined(separator: ", "))") }
        }

        return PackageDetail(name: name, version: version, description: desc, homepage: homepage, license: license, dependencies: deps, installedSize: nil, rawInfo: infoLines.joined(separator: "\n"))
    }

    private func parsePipInfo(_ raw: String, name: String) -> PackageDetail {
        var desc: String?
        var homepage: String?
        var license: String?
        var version: String?
        var location: String?
        var deps: [String] = []

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Summary:") {
                desc = trimmed.replacingOccurrences(of: "Summary: ", with: "")
            }
            if trimmed.hasPrefix("Home-page:") {
                homepage = trimmed.replacingOccurrences(of: "Home-page: ", with: "")
            }
            if trimmed.hasPrefix("License:") {
                license = trimmed.replacingOccurrences(of: "License: ", with: "")
            }
            if trimmed.hasPrefix("Version:") {
                version = trimmed.replacingOccurrences(of: "Version: ", with: "")
            }
            if trimmed.hasPrefix("Location:") {
                location = trimmed.replacingOccurrences(of: "Location: ", with: "")
            }
            if trimmed.hasPrefix("Requires:") {
                let reqStr = trimmed.replacingOccurrences(of: "Requires: ", with: "")
                deps = reqStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        }

        return PackageDetail(name: name, version: version, description: desc, homepage: homepage, license: license, dependencies: deps, installedSize: location, rawInfo: raw)
    }

    /// gem info → "name (version)\n    Authors: ...\n    Homepage: ...\n    License: ...\n    Installed at: ...\n\n    description"
    private func parseGemInfo(_ raw: String, name: String) -> PackageDetail {
        var version: String?
        var desc: String?
        var homepage: String?
        var license: String?
        var location: String?
        var authors: String?

        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "cocoapods (1.11.3)"
            if trimmed.contains("(") && trimmed.contains(")") && version == nil {
                let pattern = /\((.+?)\)/
                if let match = trimmed.firstMatch(of: pattern) {
                    version = String(match.1)
                }
            }
            if trimmed.hasPrefix("Authors:") || trimmed.hasPrefix("Author:") {
                authors = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("Homepage:") {
                homepage = trimmed.replacingOccurrences(of: "Homepage: ", with: "")
            }
            if trimmed.hasPrefix("License:") {
                license = trimmed.replacingOccurrences(of: "License: ", with: "")
            }
            if trimmed.hasPrefix("Installed at") {
                location = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        // Last non-empty line is usually the description
        if let lastLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty &&
            !$0.contains("***") && !$0.contains("(") && !$0.contains("Authors") &&
            !$0.contains("Homepage") && !$0.contains("License") && !$0.contains("Installed at") }) {
            desc = lastLine.trimmingCharacters(in: .whitespaces)
        }

        var infoLines: [String] = []
        infoLines.append("\(name) \(version ?? "")")
        if let desc = desc { infoLines.append(desc) }
        if let homepage = homepage { infoLines.append("Homepage: \(homepage)") }
        if let license = license { infoLines.append("License: \(license)") }
        if let authors = authors { infoLines.append("Authors: \(authors)") }
        if let location = location { infoLines.append("Installed at: \(location)") }

        return PackageDetail(name: name, version: version, description: desc, homepage: homepage, license: license, dependencies: [], installedSize: location, rawInfo: infoLines.joined(separator: "\n"))
    }

    // MARK: - List Parsers

    private func parseBrewList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            guard let name = parts.first, !name.isEmpty else { return nil }
            let version = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : nil
            return InstalledPackage(name: name, version: version)
        }
    }

    private func parseNpmList(_ output: String) -> [InstalledPackage] {
        // npm list -g --depth=0 --json → {"dependencies":{"pkg":{"version":"1.0.0"},...}}
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deps = json["dependencies"] as? [String: Any] else {
            return []
        }
        return deps.compactMap { (name, value) in
            guard let info = value as? [String: Any] else { return nil }
            let version = info["version"] as? String
            return InstalledPackage(name: name, version: version)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// pnpm list -g --depth=0 → tree format with ├── pkg@version
    private func parsePnpmList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("@") else { return nil }
            // Strip tree drawing characters — keep only alphanumeric, @, /, ., _, -
            let cleaned = trimmed.replacingOccurrences(of: "[^a-zA-Z0-9@/._-]", with: "", options: .regularExpression)
            guard !cleaned.isEmpty, cleaned.contains("@") else { return nil }
            if let atRange = cleaned.range(of: "@", options: .backwards) {
                let name = String(cleaned[cleaned.startIndex..<atRange.lowerBound])
                let version = String(cleaned[atRange.upperBound...])
                guard !name.isEmpty else { return nil }
                return InstalledPackage(name: name, version: version)
            }
            return InstalledPackage(name: cleaned)
        }
    }

    private func parseYarnList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            let pattern = /([^@\s"]+)@(\S+)/
            if let match = cleaned.firstMatch(of: pattern) {
                return InstalledPackage(name: String(match.1), version: String(match.2))
            }
            return nil
        }
    }

    private func parsePipList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = parts.first, !name.isEmpty, !name.starts(with: "-") else { return nil }
            let version = parts.count > 1 ? parts[1] : nil
            return InstalledPackage(name: name, version: version)
        }
    }

    private func parseGemList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty, !cleaned.starts(with: "***") else { return nil }
            let pattern = /^(.+?)\s+\((.+)\)$/
            if let match = cleaned.firstMatch(of: pattern) {
                let versions = String(match.2)
                let firstVersion = versions.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
                return InstalledPackage(name: String(match.1), version: firstVersion)
            }
            return InstalledPackage(name: cleaned)
        }
    }

    private func parseCargoList(_ output: String) -> [InstalledPackage] {
        var packages: [InstalledPackage] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                let pattern = /^(.+?)\s+v(.+):$/
                if let match = trimmed.firstMatch(of: pattern) {
                    packages.append(InstalledPackage(name: String(match.1), version: String(match.2)))
                }
            }
        }
        return packages
    }

    private func parseGoList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return InstalledPackage(name: name)
        }
    }

    private func parseComposerList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2)
            guard parts.count >= 1, !parts[0].isEmpty else { return nil }
            let name = String(parts[0])
            let version = parts.count > 1 ? String(parts[1]) : nil
            let summary = parts.count > 2 ? String(parts[2]) : nil
            return InstalledPackage(name: name, version: version, summary: summary)
        }
    }

    private func parsePodList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            let pattern = /^-\s+(.+?)\s+\((.+)\)$/
            if let match = cleaned.firstMatch(of: pattern) {
                return InstalledPackage(name: String(match.1), version: String(match.2))
            }
            return nil
        }
    }

    /// pipx list --short → "package 1.2.3" per line
    private func parsePipxList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            let name = String(parts[0])
            let version = parts.count > 1 ? String(parts[1]) : nil
            return InstalledPackage(name: name, version: version)
        }
    }

    /// conda list → "name    version    build    channel" columns
    private func parseCondaList(_ output: String) -> [InstalledPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.split(separator: " ").map(String.init)
            guard !parts.isEmpty else { return nil }
            let name = parts[0]
            let version = parts.count > 1 ? parts[1] : nil
            return InstalledPackage(name: name, version: version)
        }
    }

    /// conda update --dry-run → "name  old_ver  new_ver  channel"
    private func parseCondaOutdated(_ output: String) -> [OutdatedPackage] {
        output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("The following") else { return nil }
            let parts = trimmed.split(separator: " ").map(String.init)
            guard parts.count >= 3 else { return nil }
            return OutdatedPackage(name: parts[0], currentVersion: parts[1], latestVersion: parts[2])
        }
    }

    // MARK: - Search Parsers

    /// brew search → one result per line, may have "==> Formulae" / "==> Casks" headers
    private func parseBrewSearch(_ output: String) -> [PackageSearchResult] {
        output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
            .prefix(50)
            .map { PackageSearchResult(name: $0) }
    }

    /// npm search → multi-line format: name, description, version, maintainers, keywords, url, blank line
    private func parseNpmSearch(_ output: String) -> [PackageSearchResult] {
        let lines = output.components(separatedBy: "\n")
        var results: [PackageSearchResult] = []
        var i = 0
        while i < lines.count && results.count < 50 {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            // Package name line: starts with a non-empty name (not Version/Maintainers/Keywords/https)
            guard !line.isEmpty,
                  !line.hasPrefix("Version "),
                  !line.hasPrefix("Maintainers:"),
                  !line.hasPrefix("Keywords:"),
                  !line.hasPrefix("https://") else {
                i += 1
                continue
            }
            let name = line
            var desc: String?
            var version: String?
            // Read following lines for this package
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty {
                    i += 1
                    break
                } else if next.hasPrefix("Version ") {
                    // "Version 1.2.3 published 2024-01-01 by user"
                    let parts = next.split(separator: " ")
                    if parts.count >= 2 {
                        version = String(parts[1])
                    }
                } else if next.hasPrefix("Maintainers:") || next.hasPrefix("Keywords:") || next.hasPrefix("https://") {
                    // Skip metadata lines
                } else if desc == nil {
                    desc = next
                }
                i += 1
            }
            results.append(PackageSearchResult(name: name, version: version, description: desc))
        }
        return results
    }

    /// gem search → "name (version)"
    private func parseGemSearch(_ output: String) -> [PackageSearchResult] {
        output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("***") else { return nil }
            if let range = trimmed.range(of: " (") {
                let name = String(trimmed[..<range.lowerBound])
                let version = String(trimmed[range.upperBound...]).replacingOccurrences(of: ")", with: "")
                return PackageSearchResult(name: name, version: version)
            }
            return PackageSearchResult(name: trimmed)
        }.prefix(50).map { $0 }
    }

    /// composer search → "name description"
    private func parseComposerSearch(_ output: String) -> [PackageSearchResult] {
        output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard let name = parts.first else { return nil }
            let desc = parts.count > 1 ? parts[1] : nil
            return PackageSearchResult(name: name, description: desc)
        }.prefix(50).map { $0 }
    }
}
