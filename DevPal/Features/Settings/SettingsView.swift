import SwiftUI
import Sparkle

struct SettingsView: View {
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
    }
    private var bundleId: String {
        Bundle.main.bundleIdentifier ?? "未知"
    }
    private var swiftVersion: String {
        #if swift(>=6.0)
        "6.0+"
        #elseif swift(>=5.9)
        "5.9"
        #else
        "5.x"
        #endif
    }
    private var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    private var cpuArch: String {
        #if arch(arm64)
        "Apple Silicon (arm64)"
        #else
        "Intel (x86_64)"
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // App Info
                aboutSection

                Divider()

                // System Info
                systemSection

                Divider()

                // Update
                updateSection

                Divider()

                // Data
                dataSection

                Spacer()
            }
            .padding(24)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("关于 DevPal", systemImage: "info.circle")
                .font(.system(size: 16, weight: .semibold))

            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("DevPal")
                        .font(.system(size: 20, weight: .bold))
                    Text("macOS 开发者工具箱")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            infoGrid([
                ("版本", "\(appVersion) (\(buildNumber))"),
                ("Bundle ID", bundleId),
                ("最低系统要求", "macOS 14.0 Sonoma"),
            ])
        }
    }

    // MARK: - System

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("系统信息", systemImage: "desktopcomputer")
                .font(.system(size: 16, weight: .semibold))

            infoGrid([
                ("macOS 版本", macOSVersion),
                ("CPU 架构", cpuArch),
                ("Swift 版本", swiftVersion),
                ("Shell", ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"),
                ("用户", NSUserName()),
                ("主目录", NSHomeDirectory()),
            ])
        }
    }

    // MARK: - Update

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("软件更新", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .semibold))

            HStack(spacing: 12) {
                Button {
                    updaterViewModel.checkForUpdates()
                } label: {
                    Label("检查更新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!updaterViewModel.canCheckForUpdates)

                Toggle("自动检查更新", isOn: Binding(
                    get: { updaterViewModel.updater.automaticallyChecksForUpdates },
                    set: { updaterViewModel.updater.automaticallyChecksForUpdates = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            }

            Text("更新通过 Sparkle 框架分发，源地址为 GitHub Releases。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("数据管理", systemImage: "externaldrive")
                .font(.system(size: 16, weight: .semibold))

            HStack(spacing: 12) {
                Button {
                    UserDefaults.standard.removeObject(forKey: "sidebarOrder")
                } label: {
                    Label("重置侧边栏顺序", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("DevPal 不收集任何用户数据，所有操作均在本地完成。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func infoGrid(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .trailing)
                    Text(row.1)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
