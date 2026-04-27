import SwiftUI
import Sparkle

@main
struct DevPalApp: App {
    @StateObject private var updaterViewModel = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updaterViewModel)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 620)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新...") {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)
                .keyboardShortcut("U", modifiers: [.command])
            }
        }
    }
}
