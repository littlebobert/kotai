import AppKit
import SwiftUI

@main
struct KotaiApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }

        Settings {
            if controller.shouldShowSetupWizard {
                SetupWizardView(controller: controller)
            } else {
                SettingsView(controller: controller)
            }
        }

        Window("About Kotai", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Kotai Diagnostics", id: "diagnostics") {
            DiagnosticsView(controller: controller)
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuBarContent: View {
    let controller: AppController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ForEach(AccountMode.allCases, id: \.self) { accountMode in
            Button {
                controller.selectAccountMode(accountMode)
            } label: {
                if controller.accountMode == accountMode {
                    Label(accountMode.displayName, systemImage: "checkmark")
                } else {
                    Text(accountMode.displayName)
                }
            }
        }

        Divider()

        Button("Run Setup…") {
            controller.beginSetupWizard()
            presentSettingsWindow(openSettings: openSettings)
        }

        Button("Settings…") {
            controller.completeSetupWizard()
            presentSettingsWindow(openSettings: openSettings)
        }
        .keyboardShortcut(",")

        Button("Diagnostics…") {
            presentDiagnosticsWindow(openWindow: openWindow)
        }

        Button("About Kotai…") {
            presentAboutWindow(openWindow: openWindow)
        }

        Divider()

        Button("Quit Kotai") {
            controller.quit()
        }
        .keyboardShortcut("q")
    }
}

private struct MenuBarLabel: View {
    let controller: AppController

    @Environment(\.openSettings) private var openSettings
    @State private var hasStarted = false
    @State private var hasPresentedInitialSetup = false

    var body: some View {
        Label(
            "Kotai: \(controller.accountMode.displayName)",
            systemImage: "signpost.right.and.left"
        )
        .task {
            guard !hasStarted else {
                return
            }
            hasStarted = true
            controller.start()
        }
        .onChange(of: controller.isSetupRequired, initial: true) {
            guard controller.isSetupRequired, !hasPresentedInitialSetup else {
                return
            }
            hasPresentedInitialSetup = true
            controller.beginSetupWizard()
            presentSettingsWindow(openSettings: openSettings)
        }
    }
}
