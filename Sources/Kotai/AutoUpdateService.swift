import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class AutoUpdateService {
    private(set) var canCheckForUpdates = false

    private var updaterController: SPUStandardUpdaterController?
    private var canCheckForUpdatesObservation: NSKeyValueObservation?

    func start() {
        guard updaterController == nil else {
            return
        }

        KotaiLogger.shared.info("Starting update service")
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController
        canCheckForUpdatesObservation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
                KotaiLogger.shared.info(
                    "Update check availability: \(updater.canCheckForUpdates)"
                )
            }
        }
    }

    func checkForUpdates() {
        start()
        KotaiLogger.shared.info("Manual update check requested")
        updaterController?.checkForUpdates(nil)
    }
}
