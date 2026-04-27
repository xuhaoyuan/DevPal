import SwiftUI
import Sparkle

/// Wraps SPUStandardUpdaterController for SwiftUI usage
final class UpdaterViewModel: ObservableObject {
    let updaterController: SPUStandardUpdaterController

    init() {
        // Automatically checks for updates on launch
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater {
        updaterController.updater
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }
}
