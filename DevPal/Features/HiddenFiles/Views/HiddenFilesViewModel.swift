import SwiftUI
import Combine

@MainActor
class HiddenFilesViewModel: ObservableObject {
    @Published var isShowingHiddenFiles = false
    @Published var isToggling = false
    @Published var shortcuts = HiddenFileShortcut.defaults
    @Published var droppedFiles: [DroppedFileInfo] = []
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private var pollTimer: Timer?

    init() {
        readCurrentState()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Read Current State

    func readCurrentState() {
        Task {
            let result = try? await Shell.run("defaults read com.apple.finder AppleShowAllFiles 2>/dev/null")
            let output = (result?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            isShowingHiddenFiles = (output == "1" || output == "yes" || output == "true")
        }
    }

    // MARK: - Toggle

    func toggleHiddenFiles() async {
        isToggling = true
        defer { isToggling = false }

        let newValue = !isShowingHiddenFiles
        let boolStr = newValue ? "true" : "false"

        do {
            let writeResult = try await Shell.run("defaults write com.apple.finder AppleShowAllFiles -bool \(boolStr)")
            guard writeResult.succeeded else {
                errorMessage = "设置失败: \(writeResult.stderr)"
                return
            }

            // Restart Finder
            _ = try await Shell.run("killall Finder")

            // Wait for Finder to restart, then read back state
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            isShowingHiddenFiles = newValue
            successMessage = newValue ? "隐藏文件已显示" : "隐藏文件已隐藏"
        } catch {
            errorMessage = "切换失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.readCurrentState()
        }
    }

    // MARK: - Open in Finder

    func openInFinder(_ shortcut: HiddenFileShortcut) {
        let path = shortcut.expandedPath
        if shortcut.isDirectory {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } else {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
        }
    }

    func openInTerminal(_ shortcut: HiddenFileShortcut) {
        let dir = shortcut.isDirectory ? shortcut.expandedPath : (shortcut.expandedPath as NSString).deletingLastPathComponent
        Task {
            _ = try? await Shell.run("open -a Terminal \(dir.shellEscaped)")
        }
    }

    // MARK: - Single File Hidden Attribute

    func checkFileHidden(at path: String) async -> Bool {
        guard let result = try? await Shell.run("ls -lO \(path.shellEscaped) 2>/dev/null") else { return false }
        return result.stdout.contains("hidden")
    }

    func handleDroppedFile(url: URL) async {
        let path = url.path
        let isHidden = await checkFileHidden(at: path)
        let info = DroppedFileInfo(path: path, isHidden: isHidden)
        droppedFiles.insert(info, at: 0)
    }

    func toggleFileHidden(_ file: DroppedFileInfo) async {
        let flag = file.isHidden ? "nohidden" : "hidden"
        do {
            let result = try await Shell.run("chflags \(flag) \(file.path.shellEscaped)")
            if result.succeeded {
                if let index = droppedFiles.firstIndex(where: { $0.id == file.id }) {
                    droppedFiles[index].isHidden.toggle()
                }
                successMessage = file.isHidden ? "\(file.name) 已取消隐藏" : "\(file.name) 已隐藏"
            } else {
                errorMessage = "操作失败: \(result.stderr)"
            }
        } catch {
            errorMessage = "操作失败: \(error.localizedDescription)"
        }
    }

    func removeDroppedFile(_ file: DroppedFileInfo) {
        droppedFiles.removeAll { $0.id == file.id }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
