import Foundation

/// Represents a commonly used hidden file/directory shortcut
struct HiddenFileShortcut: Identifiable {
    let id = UUID()
    let path: String
    let label: String
    let icon: String     // SF Symbol name
    let isDirectory: Bool

    var expandedPath: String {
        (path as NSString).expandingTildeInPath
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: expandedPath)
    }

    static let defaults: [HiddenFileShortcut] = [
        HiddenFileShortcut(path: "~/.ssh/", label: "SSH 密钥与配置", icon: "key.fill", isDirectory: true),
        HiddenFileShortcut(path: "~/.gitconfig", label: "Git 全局配置", icon: "arrow.triangle.branch", isDirectory: false),
        HiddenFileShortcut(path: "~/.zshrc", label: "Zsh 配置", icon: "terminal.fill", isDirectory: true),
        HiddenFileShortcut(path: "~/.config/", label: "工具配置目录", icon: "gearshape.fill", isDirectory: true),
        HiddenFileShortcut(path: "~/Library/", label: "用户 Library", icon: "building.columns.fill", isDirectory: true),
        HiddenFileShortcut(path: "/etc/hosts", label: "Hosts 文件", icon: "network", isDirectory: false),
    ]
}

/// Represents a file dropped by user for hidden attribute management
struct DroppedFileInfo: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    var isHidden: Bool

    init(path: String, isHidden: Bool) {
        self.path = path
        self.name = (path as NSString).lastPathComponent
        self.isHidden = isHidden
    }
}
