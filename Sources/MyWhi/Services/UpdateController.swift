import AppKit
import Foundation
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates(_ sender: Any? = nil) {
        updaterController.checkForUpdates(sender)
    }
}
