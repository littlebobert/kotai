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
    }
}

@MainActor
final class KotaiAppDelegate: NSObject, NSApplicationDelegate {
    private var aboutWindowController: AboutWindowController?
    private var diagnosticsWindowController: DiagnosticsWindowController?
    private weak var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        presentDiagnostics()
        return true
    }

    func configure(controller: AppController) {
        guard self.controller !== controller else {
            return
        }
        self.controller = controller
        diagnosticsWindowController = DiagnosticsWindowController(
            controller: controller
        )
    }

    func presentAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.present()
    }

    func presentDiagnostics() {
        guard let controller else {
            return
        }
        if diagnosticsWindowController == nil {
            diagnosticsWindowController = DiagnosticsWindowController(
                controller: controller
            )
        }
        diagnosticsWindowController?.present()
    }
}

@MainActor
private final class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "About Kotai")
        configureCenteredTitle(
            String(localized: "About Kotai"),
            in: window
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AboutView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        guard let window else {
            return
        }
        activateApplication()
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class DiagnosticsWindowController: NSWindowController {
    init(controller: AppController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Kotai Diagnostics")
        configureCenteredTitle(
            String(localized: "Kotai Diagnostics"),
            in: window
        )
        window.minSize = NSSize(width: 560, height: 360)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: DiagnosticsView(controller: controller)
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        guard let window else {
            return
        }
        activateApplication()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private func configureCenteredTitle(_ title: String, in window: NSWindow) {
    window.titleVisibility = .hidden
    window.titlebarSeparatorStyle = .none

    guard
        let closeButton = window.standardWindowButton(.closeButton),
        let titlebarView = closeButton.superview
    else {
        return
    }

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(
        ofSize: NSFont.systemFontSize,
        weight: .semibold
    )
    titleLabel.alignment = .center
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titlebarView.addSubview(titleLabel)
    NSLayoutConstraint.activate([
        titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
        titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
    ])
}

@MainActor
private func activateApplication() {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSRunningApplication.current.activate(options: [.activateAllWindows])
}
