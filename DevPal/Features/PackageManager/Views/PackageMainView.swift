import SwiftUI

struct PackageMainView: View {
    @ObservedObject var viewModel: PackageViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Message bars
            if let error = viewModel.errorMessage {
                messageBar(text: error, isError: true)
            }
            if let success = viewModel.successMessage {
                messageBar(text: success, isError: false)
            }

            if viewModel.isLoading && viewModel.managers.isEmpty {
                Spacer()
                ProgressView("正在检测包管理器...")
                Spacer()
            } else if viewModel.managers.isEmpty {
                emptyState
            } else {
                PersistentSplitView(id: "package", minWidth: 140, maxWidth: 260, defaultWidth: 180) {
                    sidebar
                } content: {
                    Group {
                        if let manager = viewModel.selectedManager {
                            PackageListView(viewModel: viewModel, manager: manager)
                        } else {
                            Text("请选择一个包管理器")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { await viewModel.refresh() }
        .alert("确认卸载", isPresented: $viewModel.showUninstallConfirm) {
            Button("取消", role: .cancel) { viewModel.packageToUninstall = nil }
            Button("卸载", role: .destructive) {
                Task { await viewModel.executeUninstall() }
            }
        } message: {
            if let pkg = viewModel.packageToUninstall {
                Text("确定要卸载 \(pkg.name) 吗？此操作不可撤销。")
            }
        }
        .sheet(isPresented: $viewModel.showInstallSheet) {
            PackageInstallSheet(viewModel: viewModel)
        }
        .alert("确认卸载包管理器", isPresented: $viewModel.showUninstallManagerConfirm) {
            Button("取消", role: .cancel) { viewModel.managerToUninstall = nil }
            Button("卸载", role: .destructive) {
                Task { await viewModel.executeUninstallManager() }
            }
        } message: {
            if let def = viewModel.managerToUninstall {
                Text("确定要卸载 \(def.displayName) 吗？这将移除该包管理器及其配置。")
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 2) {
            ForEach(viewModel.managers) { manager in
                let isSelected = viewModel.selectedManagerId == manager.id || (viewModel.selectedManagerId == nil && viewModel.managers.first?.id == manager.id)
                Button {
                    viewModel.selectedManagerId = manager.id
                    viewModel.searchText = ""
                    viewModel.showCaskOnly = false
                    viewModel.showFormulaOnly = false
                    viewModel.showOutdatedOnly = false
                    viewModel.clearDetail()
                    Task { await viewModel.loadManagerIfNeeded(manager.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: manager.icon)
                            .font(.system(size: 12))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(manager.name)
                                    .font(.system(size: 12, weight: .medium))
                                if !manager.outdatedPackages.isEmpty {
                                    Text("\(manager.outdatedPackages.count)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.orange))
                                }
                            }
                            HStack(spacing: 4) {
                                Text("\(manager.packages.count) 个包")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                if let disk = manager.diskUsage {
                                    Text("· \(disk)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if manager.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .foregroundColor(isSelected ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let def = PackageManagerDefinition(rawValue: manager.id), def.managerUninstallScript != nil {
                        Button(role: .destructive) {
                            viewModel.confirmUninstallManager(def)
                        } label: {
                            Label("卸载 \(manager.name)", systemImage: "trash")
                        }
                    }
                }
            }

            // Uninstalled managers section
            if !viewModel.uninstalledManagers.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Text("未安装")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)

                ForEach(viewModel.uninstalledManagers, id: \.rawValue) { def in
                    HStack(spacing: 8) {
                        Image(systemName: def.icon)
                            .font(.system(size: 12))
                            .frame(width: 18)
                            .foregroundColor(.secondary)
                        Text(def.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        if viewModel.isInstallingManager {
                            ProgressView()
                                .controlSize(.mini)
                        } else if def.managerInstallScript != nil {
                            Button {
                                Task { await viewModel.installManager(def) }
                            } label: {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("安装 \(def.displayName)")
                        } else if let hint = def.managerInstallHint {
                            Button {
                                viewModel.successMessage = "\(def.displayName): \(hint)"
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(hint)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
            }

            Spacer()

            // Check outdated button
            Button {
                Task { await viewModel.checkAllOutdated() }
            } label: {
                HStack(spacing: 4) {
                    if viewModel.isCheckingOutdated {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 11))
                    }
                    Text("检查更新")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading || viewModel.isCheckingOutdated)

            // Refresh all button
            Button {
                Task { await viewModel.refresh() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("全部刷新")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("未检测到包管理器")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Text("支持 Homebrew, npm, yarn, pnpm, pip3, pipx, conda, gem, cargo, go, composer, CocoaPods")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("重新检测") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Message Bar

    private func messageBar(text: String, isError: Bool) -> some View {
        HStack {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(text).font(.system(size: 12))
            Spacer()
            Button { viewModel.clearMessages() } label: {
                Image(systemName: "xmark").font(.system(size: 10))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(isError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
    }
}

// MARK: - Package List View

struct PackageListView: View {
    @ObservedObject var viewModel: PackageViewModel
    let manager: PackageManagerInfo

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            if let error = manager.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error).font(.system(size: 12))
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }

            // Health report
            if let report = manager.healthReport {
                healthReportBar(report)
            }

            // Main content area
            if manager.isLoading {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if viewModel.filteredPackages.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: viewModel.searchText.isEmpty ? "tray" : "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text(viewModel.searchText.isEmpty ? "暂无已安装的包" : "未找到匹配的包")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                HSplitView {
                    packageTable
                        .frame(minWidth: 300)

                    // Detail panel
                    if viewModel.selectedPackage != nil {
                        PackageDetailPanel(viewModel: viewModel)
                            .frame(minWidth: 260, idealWidth: 340, maxWidth: 420)
                    }
                }
            }

            Divider()

            // Status bar
            statusBar
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Manager info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: manager.icon)
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                        Text(manager.name)
                            .font(.system(size: 13, weight: .medium))
                        if !manager.outdatedPackages.isEmpty {
                            Text("\(manager.outdatedPackages.count) 个可更新")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                    if let version = manager.version {
                        Text(version)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("搜索包名...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(maxWidth: 200)
            }

            // Filter & action row
            HStack(spacing: 8) {
                // Sort
                Menu {
                    ForEach(PackageSortOrder.allCases, id: \.self) { order in
                        Button {
                            if viewModel.sortOrder == order {
                                viewModel.sortAscending.toggle()
                            } else {
                                viewModel.sortOrder = order
                                viewModel.sortAscending = true
                            }
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if viewModel.sortOrder == order {
                                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10))
                        Text(viewModel.sortOrder.rawValue)
                            .font(.system(size: 10))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Brew-specific filters
                if manager.id == "brew" {
                    Divider().frame(height: 14)

                    filterToggle("全部", isActive: !viewModel.showCaskOnly && !viewModel.showFormulaOnly) {
                        viewModel.showCaskOnly = false
                        viewModel.showFormulaOnly = false
                    }
                    filterToggle("Formula", isActive: viewModel.showFormulaOnly) {
                        viewModel.showFormulaOnly = true
                        viewModel.showCaskOnly = false
                    }
                    filterToggle("Cask", isActive: viewModel.showCaskOnly) {
                        viewModel.showCaskOnly = true
                        viewModel.showFormulaOnly = false
                    }
                }

                // Outdated filter
                if !manager.outdatedPackages.isEmpty {
                    Divider().frame(height: 14)
                    filterToggle("可更新 (\(manager.outdatedPackages.count))", isActive: viewModel.showOutdatedOnly) {
                        viewModel.showOutdatedOnly.toggle()
                    }
                }

                Spacer()

                // Action buttons
                if PackageManagerDefinition(rawValue: manager.id)?.outdatedCommand != nil {
                    Button {
                        Task { await viewModel.checkOutdated() }
                    } label: {
                        HStack(spacing: 2) {
                            if viewModel.isCheckingOutdated {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 11))
                            }
                            Text("检查更新")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isCheckingOutdated)
                }

                Menu {
                    Button { viewModel.exportList() } label: {
                        Label("复制列表到剪贴板", systemImage: "doc.on.clipboard")
                    }
                    Button { viewModel.exportListToFile() } label: {
                        Label("导出列表到文件...", systemImage: "square.and.arrow.up")
                    }
                    if PackageManagerDefinition(rawValue: manager.id)?.healthCommand != nil {
                        Divider()
                        Button {
                            Task { await viewModel.runHealthCheck() }
                        } label: {
                            Label("健康检查", systemImage: "stethoscope")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if PackageManagerDefinition(rawValue: manager.id)?.installCommandPrefix != nil {
                    Button {
                        viewModel.openInstallSheet()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                            Text("安装")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    Task { await viewModel.refreshManager(manager.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private func filterToggle(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .accentColor : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Health Report

    private func healthReportBar(_ report: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundColor(.blue)
                Text("健康检查结果")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button {
                    if let idx = viewModel.managers.firstIndex(where: { $0.id == manager.id }) {
                        viewModel.managers[idx].healthReport = nil
                    }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9))
                }.buttonStyle(.plain)
            }
            ReadOnlyTextView(text: report, font: .monospacedSystemFont(ofSize: 10, weight: .regular))
                .frame(maxHeight: 120)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.blue.opacity(0.05))
    }

    // MARK: - Package Table

    private var packageTable: some View {
        List(selection: Binding(
            get: { viewModel.selectedPackage },
            set: { pkg in
                if let pkg = pkg {
                    Task { await viewModel.loadPackageDetail(pkg) }
                } else {
                    viewModel.clearDetail()
                }
            }
        )) {
            // Header
            HStack {
                Text("包名")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if manager.id == "brew" {
                    Text("类型")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)
                }
                Text("版本")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 120, alignment: .leading)
                Text("最新")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
            }
            .listRowSeparator(.visible)

            ForEach(viewModel.filteredPackages) { pkg in
                let outdated = viewModel.outdatedInfo(for: pkg.name)
                HStack {
                    Text(pkg.name)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if manager.id == "brew" {
                        Text(pkg.isCask ? "Cask" : "Formula")
                            .font(.system(size: 10))
                            .foregroundColor(pkg.isCask ? .purple : .secondary)
                            .frame(width: 60, alignment: .leading)
                    }
                    Text(pkg.version ?? "—")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .leading)
                    if let outdated = outdated {
                        Text(outdated.latestVersion)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.orange)
                            .frame(width: 80, alignment: .leading)
                    } else {
                        Text("—")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                            .frame(width: 80, alignment: .leading)
                    }
                }
                .tag(pkg)
                .padding(.vertical, 1)
                .contextMenu {
                    Button {
                        viewModel.copyPackageInfo(pkg)
                    } label: {
                        Label("复制 \(pkg.name)@\(pkg.version ?? "")", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        Task { await viewModel.loadPackageDetail(pkg) }
                    } label: {
                        Label("查看详情", systemImage: "info.circle")
                    }
                    if viewModel.selectedDefinition?.uninstallCommandPrefix != nil {
                        Divider()
                        Button(role: .destructive) {
                            viewModel.confirmUninstall(pkg)
                        } label: {
                            Label("卸载 \(pkg.name)", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if let path = manager.path {
                Text("路径: \(path)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if let disk = manager.diskUsage {
                Text("· 占用: \(disk)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if viewModel.showOutdatedOnly {
                Text("可更新 \(viewModel.filteredPackages.count) 个包")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            } else {
                Text(viewModel.searchText.isEmpty
                     ? "共 \(manager.packages.count) 个包"
                     : "筛选 \(viewModel.filteredPackages.count) / \(manager.packages.count) 个包")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Package Detail Panel

struct PackageDetailPanel: View {
    @ObservedObject var viewModel: PackageViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("包详情")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button { viewModel.clearDetail() } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if viewModel.isLoadingDetail {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if let pkg = viewModel.selectedPackage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Package name & version
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pkg.name)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                            if let v = pkg.version {
                                Text("v\(v)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            if let outdated = viewModel.outdatedInfo(for: pkg.name) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 11))
                                    Text("\(outdated.currentVersion) → \(outdated.latestVersion)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        if let detail = viewModel.packageDetail {
                            Divider()

                            if let desc = detail.description, !desc.isEmpty {
                                detailRow("描述", value: desc)
                            }
                            if let homepage = detail.homepage, !homepage.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("主页")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                    Link(homepage, destination: URL(string: homepage) ?? URL(string: "https://example.com")!)
                                        .font(.system(size: 11))
                                }
                            }
                            if let license = detail.license, !license.isEmpty {
                                detailRow("许可", value: license)
                            }
                            if let size = detail.installedSize, !size.isEmpty {
                                detailRow("位置", value: size)
                            }
                            if !detail.dependencies.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("依赖 (\(detail.dependencies.count))")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text(detail.dependencies.joined(separator: ", "))
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }

                            // Action buttons between detail and raw info
                            Divider()

                            HStack(spacing: 8) {
                                if let outdated = viewModel.outdatedInfo(for: pkg.name) {
                                    Button {
                                        Task { await viewModel.upgradeSelectedPackage() }
                                    } label: {
                                        if viewModel.isUpgrading {
                                            ProgressView()
                                                .controlSize(.mini)
                                        } else {
                                            Label("更新到 \(outdated.latestVersion)", systemImage: "arrow.up.circle")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(viewModel.isUpgrading)
                                }

                                if viewModel.selectedDefinition?.outdatedCommand != nil {
                                    Button {
                                        Task { await viewModel.checkSinglePackageOutdated() }
                                    } label: {
                                        if viewModel.isCheckingOutdated {
                                            ProgressView()
                                                .controlSize(.mini)
                                        } else {
                                            Label("检查更新", systemImage: "arrow.up.circle")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(viewModel.isCheckingOutdated)
                                }

                                if viewModel.selectedDefinition?.uninstallCommandPrefix != nil {
                                    Button(role: .destructive) {
                                        viewModel.confirmUninstall(pkg)
                                    } label: {
                                        Label("卸载", systemImage: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            Divider()

                            // Raw info
                            VStack(alignment: .leading, spacing: 4) {
                                Text("原始信息")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                ReadOnlyTextView(text: detail.rawInfo, font: .monospacedSystemFont(ofSize: 10, weight: .regular))
                                    .frame(minHeight: 100, maxHeight: 200)
                            }
                        }

                        // Copy button at bottom
                        Button {
                            viewModel.copyPackageInfo(pkg)
                        } label: {
                            Label("复制", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Install Sheet

struct PackageInstallSheet: View {
    @ObservedObject var viewModel: PackageViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("安装新包")
                    .font(.system(size: 14, weight: .semibold))
                if let def = viewModel.selectedDefinition {
                    Text("— \(def.displayName)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("输入包名搜索或直接安装...", text: $viewModel.installSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        if viewModel.selectedDefinition?.searchCommandPrefix != nil {
                            Task { await viewModel.searchPackages() }
                        } else {
                            Task { await viewModel.installDirectInput() }
                        }
                    }

                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.mini)
                }

                if viewModel.selectedDefinition?.searchCommandPrefix != nil {
                    Button("搜索") {
                        Task { await viewModel.searchPackages() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.installSearchText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSearching)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            // Brew cask toggle
            if viewModel.selectedDefinition == .brew {
                HStack {
                    Toggle("安装为 Cask（GUI 应用）", isOn: $viewModel.installAsCask)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            Divider()

            // Results or direct install
            if viewModel.selectedDefinition?.searchCommandPrefix != nil {
                // Has search support — show results
                if viewModel.installSearchResults.isEmpty && !viewModel.isSearching {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                        Text("搜索包名以查找可用的包")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List(viewModel.installSearchResults) { result in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                if let desc = result.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if let ver = result.version {
                                Text(ver)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Button("安装") {
                                Task { await viewModel.installPackage(result.name) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(viewModel.isInstalling)
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                // No search support — direct install
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("该包管理器不支持搜索，请直接输入包名后回车安装")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                Spacer()
            }

            Divider()

            // Bottom bar
            HStack {
                if viewModel.isInstalling {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在安装...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("直接安装") {
                    Task { await viewModel.installDirectInput() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.installSearchText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isInstalling)
                Button("关闭") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(12)
        }
        .frame(width: 500, height: 420)
    }
}
