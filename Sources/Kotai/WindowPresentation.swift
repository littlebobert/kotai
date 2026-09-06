import AppKit
import SwiftUI

@MainActor
func presentSettingsWindow(openSettings: OpenSettingsAction) {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSRunningApplication.current.activate(
        options: [.activateAllWindows]
    )
    openSettings()

    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(
            options: [.activateAllWindows]
        )

        let settingsWindow = NSApplication.shared.windows.first { window in
            window.title.localizedCaseInsensitiveContains("settings")
                || window.title.localizedCaseInsensitiveContains("setup")
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        WindowActivationCoordinator.shared.observeClosing(of: settingsWindow)
    }
}

@MainActor
private final class WindowActivationCoordinator: NSObject {
    static let shared = WindowActivationCoordinator()

    private weak var observedWindow: NSWindow?

    func observeClosing(of window: NSWindow?) {
        guard observedWindow !== window else {
            return
        }

        if let observedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: observedWindow
            )
        }

        observedWindow = window

        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }
    }

    @objc
    private func windowWillClose() {
        NSApplication.shared.setActivationPolicy(.accessory)
        observedWindow = nil
    }
}
