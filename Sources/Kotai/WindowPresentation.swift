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

        let expectedTitles = [
            String(localized: "Kotai Settings"),
            String(localized: "Kotai Setup"),
        ]
        let settingsWindow = NSApplication.shared.windows.first { window in
            expectedTitles.contains(window.title)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        WindowActivationCoordinator.shared.observeClosing(of: settingsWindow)
    }
}

@MainActor
func presentAboutWindow(openWindow: OpenWindowAction) {
    presentWindow(
        id: "about",
        title: String(localized: "About Kotai"),
        openWindow: openWindow
    )
}

@MainActor
func presentDiagnosticsWindow(openWindow: OpenWindowAction) {
    presentWindow(
        id: "diagnostics",
        title: String(localized: "Kotai Diagnostics"),
        openWindow: openWindow
    )
}

@MainActor
private func presentWindow(
    id: String,
    title: String,
    openWindow: OpenWindowAction
) {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSRunningApplication.current.activate(options: [.activateAllWindows])
    openWindow(id: id)

    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(
            options: [.activateAllWindows]
        )

        let presentedWindow = NSApplication.shared.windows.first { window in
            window.title == title
        }
        presentedWindow?.makeKeyAndOrderFront(nil)
        WindowActivationCoordinator.shared.observeClosing(of: presentedWindow)
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
