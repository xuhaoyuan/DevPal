import Foundation

/// Represents a package manager detected on the system
struct PackageManagerInfo: Identifiable, Hashable {
    let id: String          // e.g. "brew", "npm"
    let name: String        // e.g. "Homebrew", "npm"
    let icon: String        // SF Symbol name
    let command: String     // e.g. "brew", "npm"
    var version: String?
    var path: String?       // which <command> result
    var packages: [InstalledPackage] = []
    var outdatedPackages: [OutdatedPackage] = []
    var isLoading: Bool = false
    var hasLoaded: Bool = false
    var error: String?
    var healthReport: String?
    var diskUsage: String?

    static func == (lhs: PackageManagerInfo, rhs: PackageManagerInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.version == rhs.version &&
        lhs.packages == rhs.packages &&
        lhs.outdatedPackages == rhs.outdatedPackages &&
        lhs.isLoading == rhs.isLoading &&
        lhs.hasLoaded == rhs.hasLoaded &&
        lhs.error == rhs.error &&
        lhs.healthReport == rhs.healthReport &&
        lhs.diskUsage == rhs.diskUsage
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A single installed package
struct InstalledPackage: Identifiable, Hashable {
    var id: String { "\(name)-\(version ?? "")" }
    let name: String
    var version: String?
    var summary: String?
    var isCask: Bool = false  // Homebrew: distinguish formula vs cask
}

/// A package with available update
struct OutdatedPackage: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let currentVersion: String
    let latestVersion: String
}

/// Package detail info
struct PackageDetail {
    let name: String
    let version: String?
    let description: String?
    let homepage: String?
    let license: String?
    let dependencies: [String]
    let installedSize: String?
    let rawInfo: String
}

/// Package search result
struct PackageSearchResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var version: String?
    var description: String?
}

/// Sort options for package list
enum PackageSortOrder: String, CaseIterable {
    case name = "名称"
    case version = "版本"

    var icon: String {
        switch self {
        case .name: return "textformat.abc"
        case .version: return "number"
        }
    }
}

/// All supported package managers and their detection/listing commands
enum PackageManagerDefinition: String, CaseIterable {
    case brew
    case npm
    case yarn
    case pnpm
    case pip3
    case pipx
    case conda
    case gem
    case cargo
    case go
    case composer
    case pod

    var displayName: String {
        switch self {
        case .brew: return "Homebrew"
        case .npm: return "npm"
        case .yarn: return "Yarn"
        case .pnpm: return "pnpm"
        case .pip3: return "pip3 (Python)"
        case .pipx: return "pipx"
        case .conda: return "Conda"
        case .gem: return "gem (Ruby)"
        case .cargo: return "Cargo (Rust)"
        case .go: return "Go Modules"
        case .composer: return "Composer (PHP)"
        case .pod: return "CocoaPods"
        }
    }

    var icon: String {
        switch self {
        case .brew: return "mug.fill"
        case .npm, .yarn, .pnpm: return "shippingbox.fill"
        case .pip3: return "tortoise.fill"
        case .pipx: return "terminal.fill"
        case .conda: return "leaf.circle.fill"
        case .gem: return "diamond.fill"
        case .cargo: return "gearshape.2.fill"
        case .go: return "hare.fill"
        case .composer: return "music.note"
        case .pod: return "leaf.fill"
        }
    }

    var command: String { rawValue }

    var versionCommand: String {
        switch self {
        case .brew: return "brew --version | head -1"
        case .npm: return "npm --version"
        case .yarn: return "yarn --version"
        case .pnpm: return "pnpm --version"
        case .pip3: return "pip3 --version"
        case .pipx: return "pipx --version"
        case .conda: return "conda --version"
        case .gem: return "gem --version"
        case .cargo: return "cargo --version"
        case .go: return "go version"
        case .composer: return "composer --version 2>/dev/null | head -1"
        case .pod: return "pod --version"
        }
    }

    var listCommand: String {
        switch self {
        case .brew: return "brew list --versions"
        case .npm: return "npm list -g --depth=0 --json 2>/dev/null"
        case .yarn: return "yarn global list --depth=0 2>/dev/null"
        case .pnpm: return "pnpm list -g --depth=0 2>/dev/null | tail -n +2"
        case .pip3: return "pip3 list --format=columns 2>/dev/null | tail -n +3"
        case .pipx: return "pipx list --short 2>/dev/null"
        case .conda: return "conda list --no-pip 2>/dev/null | grep -v '^#'"
        case .gem: return "gem list --local --no-versions 2>/dev/null"
        case .cargo: return "cargo install --list 2>/dev/null"
        case .go: return "ls $(go env GOPATH 2>/dev/null)/bin 2>/dev/null"
        case .composer: return "composer global show --format=text 2>/dev/null"
        case .pod: return "pod list 2>/dev/null | head -100"
        }
    }

    var listWithVersionsCommand: String {
        switch self {
        case .gem: return "gem list --local 2>/dev/null"
        default: return listCommand
        }
    }

    /// Command to check for outdated packages
    var outdatedCommand: String? {
        switch self {
        case .brew: return "brew outdated --verbose 2>/dev/null"
        case .npm: return "npm outdated -g 2>/dev/null"
        case .pip3: return "pip3 list --outdated --format=columns 2>/dev/null | tail -n +3"
        case .pipx: return nil
        case .conda: return "conda update --all --dry-run 2>/dev/null | grep -E '^[a-z]' | grep -v '^#'"
        case .gem: return "gem outdated 2>/dev/null"
        case .cargo: return nil
        case .composer: return "composer global outdated --format=text 2>/dev/null"
        default: return nil
        }
    }

    /// Command to get info about a specific package
    var infoCommandPrefix: String? {
        switch self {
        case .brew: return "brew info --json=v1"
        case .npm: return "npm info --json"
        case .pip3: return "pip3 show"
        case .pipx: return "pipx runpip"
        case .conda: return "conda info"
        case .gem: return "gem info"
        case .cargo: return nil
        case .go: return nil
        case .composer: return "composer global show"
        case .pod: return "pod spec cat --regex"
        default: return nil
        }
    }

    /// Command to uninstall a package
    var uninstallCommandPrefix: String? {
        switch self {
        case .brew: return "brew uninstall"
        case .npm: return "npm uninstall -g"
        case .yarn: return "yarn global remove"
        case .pnpm: return "pnpm remove -g"
        case .pip3: return "pip3 uninstall -y"
        case .pipx: return "pipx uninstall"
        case .conda: return "conda remove -y"
        case .gem: return "gem uninstall"
        case .cargo: return "cargo uninstall"
        case .composer: return "composer global remove"
        case .pod: return nil
        case .go: return nil
        }
    }

    /// Command to check health
    var healthCommand: String? {
        switch self {
        case .brew: return "brew doctor 2>&1"
        case .npm: return "npm doctor 2>&1"
        default: return nil
        }
    }

    /// Command to check disk usage
    var diskUsageCommand: String? {
        switch self {
        case .brew: return "du -sh $(brew --prefix)/Cellar 2>/dev/null | awk '{print $1}'"
        case .npm: return "du -sh $(npm root -g) 2>/dev/null | awk '{print $1}'"
        case .pip3: return "du -sh $(pip3 show pip 2>/dev/null | grep Location | awk '{print $2}') 2>/dev/null | awk '{print $1}'"
        case .pipx: return "du -sh ~/.local/pipx 2>/dev/null | awk '{print $1}'"
        case .conda: return "du -sh $(conda info --base 2>/dev/null)/pkgs 2>/dev/null | awk '{print $1}'"
        case .gem: return "du -sh $(gem environment gemdir 2>/dev/null) 2>/dev/null | awk '{print $1}'"
        case .cargo: return "du -sh ~/.cargo/bin 2>/dev/null | awk '{print $1}'"
        default: return nil
        }
    }

    /// Whether this manager supports cask distinction
    var supportsCask: Bool { self == .brew }

    /// Command prefix to upgrade a specific package
    var upgradeCommandPrefix: String? {
        switch self {
        case .brew: return "brew upgrade"
        case .npm: return "npm update -g"
        case .yarn: return "yarn global upgrade"
        case .pnpm: return "pnpm update -g"
        case .pip3: return "pip3 install --upgrade"
        case .pipx: return "pipx upgrade"
        case .conda: return "conda update -y"
        case .gem: return "gem update"
        case .cargo: return "cargo install"
        case .composer: return "composer global update"
        case .pod: return "pod update"
        case .go: return nil
        }
    }

    /// Command prefix to install a new package
    var installCommandPrefix: String? {
        switch self {
        case .brew: return "brew install"
        case .npm: return "npm install -g"
        case .yarn: return "yarn global add"
        case .pnpm: return "pnpm add -g"
        case .pip3: return "pip3 install"
        case .pipx: return "pipx install"
        case .conda: return "conda install -y"
        case .gem: return "gem install"
        case .cargo: return "cargo install"
        case .composer: return "composer global require"
        case .pod: return nil
        case .go: return "go install"
        }
    }

    /// Command to search for packages (nil = no search support, user types name directly)
    var searchCommandPrefix: String? {
        switch self {
        case .brew: return "brew search"
        case .npm: return "npm search"
        case .pip3: return nil  // pip search is deprecated
        case .gem: return "gem search"
        case .cargo: return nil  // cargo search requires crates.io
        case .composer: return "composer global search"
        default: return nil
        }
    }

    /// Shell script to install this package manager (nil = cannot auto-install)
    var managerInstallScript: String? {
        switch self {
        case .brew: return "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        case .npm: return nil  // Comes with Node.js
        case .yarn: return "npm install -g yarn"
        case .pnpm: return "npm install -g pnpm"
        case .pip3: return nil  // Comes with Python
        case .pipx: return "brew install pipx && pipx ensurepath"
        case .conda: return nil  // Requires manual installer
        case .gem: return nil  // Comes with Ruby
        case .cargo: return "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
        case .go: return "brew install go"
        case .composer: return "brew install composer"
        case .pod: return "brew install cocoapods"
        }
    }

    /// Shell script to uninstall this package manager (nil = cannot auto-uninstall)
    var managerUninstallScript: String? {
        switch self {
        case .brew: return "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\""
        case .npm: return nil  // Part of Node.js
        case .yarn: return "npm uninstall -g yarn"
        case .pnpm: return "npm uninstall -g pnpm"
        case .pip3: return nil  // Part of Python
        case .pipx: return "brew uninstall pipx"
        case .conda: return nil  // Requires manual removal
        case .gem: return nil  // Part of Ruby
        case .cargo: return "rustup self uninstall -y"
        case .go: return "brew uninstall go"
        case .composer: return "brew uninstall composer"
        case .pod: return "brew uninstall cocoapods"
        }
    }

    /// Hint for manual installation when auto-install is not available
    var managerInstallHint: String? {
        switch self {
        case .npm: return "请安装 Node.js: https://nodejs.org"
        case .pip3: return "请安装 Python: https://www.python.org"
        case .conda: return "请安装 Miniconda: https://docs.conda.io"
        case .gem: return "macOS 自带 Ruby，如需更新请使用 rbenv"
        default: return nil
        }
    }
}
