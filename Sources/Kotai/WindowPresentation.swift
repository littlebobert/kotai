import AppKit
import Observation
import SwiftUI

@MainActor
final class KotaiAppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    let usageMenuBarSettings = UsageMenuBarSettings()

    private var aboutWindowController: AboutWindowController?
    private var diagnosticsWindowController: DiagnosticsWindowController?
    private var usageWindowController: UsageWindowController?
    private var setupWindowController: SetupWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var hasPresentedInitialSetup = false
    private var usageStatusItem: NSStatusItem?
    private var usageStatusTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        guard ApplicationLaunchEnvironment.shouldStartRuntime(
            environment: ProcessInfo.processInfo.environment
        ) else {
            return
        }
        observeSetupRequirement()
        controller.start()
        configureUsageStatusItem()
        presentUsageStatistics()
        Task { @MainActor [weak self] in
            guard let self, await controller.requiresManagedSetupUpgrade() else { return }
            presentSetup()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        presentUsageStatistics()
        return true
    }

    func presentSettings() {
        controller.completeSetupWizard()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                controller: controller,
                usageMenuBarSettings: usageMenuBarSettings,
                usageMenuBarSettingsDidChange: usageMenuBarSettingsDidChange,
                openSetup: presentSetup
            )
        }
        settingsWindowController?.present()
    }

    func presentSetup() {
        controller.beginSetupWizard()
        if setupWindowController == nil {
            setupWindowController = SetupWindowController(controller: controller) { [weak self] in
                self?.setupWindowController?.close()
            }
        } else {
            setupWindowController?.resetWizard()
        }
        setupWindowController?.present()
    }

    func presentAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.present()
    }

    func presentDiagnostics() {
        if diagnosticsWindowController == nil {
            diagnosticsWindowController = DiagnosticsWindowController(
                controller: controller
            )
        }
        diagnosticsWindowController?.present()
    }


    func presentUsageStatistics() {
        if usageWindowController == nil {
            usageWindowController = UsageWindowController(controller: controller)
        }
        usageWindowController?.present()
    }


    func usageMenuBarSettingsDidChange() {
        configureUsageStatusItem()
    }

    private func configureUsageStatusItem() {
        usageStatusTask?.cancel()
        usageStatusTask = nil
        guard usageMenuBarSettings.isEnabled else {
            if let usageStatusItem { NSStatusBar.system.removeStatusItem(usageStatusItem) }
            usageStatusItem = nil
            return
        }
        if usageStatusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                let image = NSImage(
                    systemSymbolName: UsageStatusPresentation.symbolName,
                    accessibilityDescription: String(localized: "Kotai usage")
                )
                image?.isTemplate = true
                button.image = image
                button.imagePosition = .imageLeading
                button.title = "—"
            }

            let menu = NSMenu()
            menu.addItem(
                withTitle: "Usage Statistics…",
                action: #selector(showUsageFromStatusItem),
                keyEquivalent: ""
            )
            menu.addItem(
                withTitle: "Settings…",
                action: #selector(showSettingsFromStatusItem),
                keyEquivalent: ","
            )
            menu.addItem(
                withTitle: "Diagnostics…",
                action: #selector(showDiagnosticsFromStatusItem),
                keyEquivalent: ""
            )
            menu.addItem(.separator())
            menu.addItem(
                withTitle: "Quit Kotai",
                action: #selector(quitFromStatusItem),
                keyEquivalent: "q"
            )
            for menuItem in menu.items {
                menuItem.target = self
            }
            item.menu = menu
            usageStatusItem = item
        }
        usageStatusTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshUsageStatusItem()
                try? await Task.sleep(for: .seconds(900))
            }
        }
    }

    private func refreshUsageStatusItem() async {
        let account = usageMenuBarSettings.account
        do {
            let result = try await controller.managedUsage(for: account.mode, days: 30)
            usageStatusItem?.button?.title = UsageStatusPresentation.formattedSpend(
                result.usage.spend
            )
            usageStatusItem?.button?.toolTip = "\(account.displayName) OpenRouter workspace spend · last 30 days"
        } catch {
            usageStatusItem?.button?.title = "—"
            usageStatusItem?.button?.toolTip = error.localizedDescription
        }
    }

    @objc private func showUsageFromStatusItem() { presentUsageStatistics() }
    @objc private func showSettingsFromStatusItem() { presentSettings() }
    @objc private func showDiagnosticsFromStatusItem() { presentDiagnostics() }
    @objc private func quitFromStatusItem() { controller.quit() }

    private func observeSetupRequirement() {
        withObservationTracking {
            _ = controller.isSetupRequired
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.observeSetupRequirement()
                self.presentInitialSetupIfNeeded()
            }
        }
    }

    private func presentInitialSetupIfNeeded() {
        guard controller.isSetupRequired, !hasPresentedInitialSetup else {
            return
        }
        hasPresentedInitialSetup = true
        presentSetup()
    }
}

enum UsageStatusPresentation {
    static let currencyCode = "USD"
    static let symbolName = "signpost.right.and.left"

    static func formattedSpend(
        _ spend: Double,
        locale: Locale = .current
    ) -> String {
        let roundedSpend = spend.rounded(.toNearestOrAwayFromZero)
        return roundedSpend.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(0))
                .locale(locale)
        )
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController {
    init(
        controller: AppController,
        usageMenuBarSettings: UsageMenuBarSettings,
        usageMenuBarSettingsDidChange: @escaping () -> Void,
        openSetup: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Kotai Settings")
        configureCenteredTitle(String(localized: "Kotai Settings"), in: window)
        window.minSize = NSSize(width: 620, height: 520)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("KotaiSettingsWindow")
        if !window.setFrameUsingName("KotaiSettingsWindow") { window.center() }
        window.contentView = NSHostingView(
            rootView: SettingsView(
                controller: controller,
                usageMenuBarSettings: usageMenuBarSettings,
                usageMenuBarSettingsDidChange: usageMenuBarSettingsDidChange,
                openSetup: openSetup
            )
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        activateApplication(); showWindow(nil); window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class SetupWindowController: NSWindowController {
    private let controller: AppController
    private let onFinished: () -> Void

    init(controller: AppController, onFinished: @escaping () -> Void) {
        self.controller = controller
        self.onFinished = onFinished
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Kotai Setup")
        configureCenteredTitle(String(localized: "Kotai Setup"), in: window)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        resetWizard()
    }

    required init?(coder: NSCoder) { nil }

    func resetWizard() {
        window?.contentView = NSHostingView(
            rootView: SetupWizardView(controller: controller, onFinished: onFinished)
        )
    }

    func present() {
        guard let window else { return }
        activateApplication()
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 292, height: 270),
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
        window.setFrameAutosaveName("KotaiDiagnosticsWindow")
        if !window.setFrameUsingName("KotaiDiagnosticsWindow") {
            window.center()
        }
        window.contentView = NSHostingView(
            rootView: DiagnosticsView(controller: controller, openSetup: { [weak controller] in
                guard controller != nil else { return }
                (NSApplication.shared.delegate as? KotaiAppDelegate)?.presentSetup()
            })
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
private final class UsageWindowController: NSWindowController {
    init(controller: AppController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Usage Statistics")
        configureCenteredTitle(String(localized: "Usage Statistics"), in: window)
        window.minSize = NSSize(width: 680, height: 520)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("KotaiUsageStatisticsWindow")
        if !window.setFrameUsingName("KotaiUsageStatisticsWindow") { window.center() }
        window.contentView = NSHostingView(rootView: UsageStatisticsView(controller: controller))
        super.init(window: window)
    }
    required init?(coder: NSCoder) { nil }
    func present() {
        guard let window else { return }
        activateApplication(); showWindow(nil); window.makeKeyAndOrderFront(nil)
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
