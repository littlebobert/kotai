import AppKit
import SwiftUI

@main
struct KotaiApp: App {
    @NSApplicationDelegateAdaptor(KotaiAppDelegate.self) private var appDelegate
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: controller, appDelegate: appDelegate)
        } label: {
            MenuBarLabel(controller: controller, appDelegate: appDelegate)
        }
        .commands {
            NativeEditingCommands()
        }

        Settings {
            if controller.shouldShowSetupWizard {
                SetupWizardView(controller: controller)
            } else {
                SettingsView(controller: controller)
            }
        }
    }
}

private struct MenuBarContent: View {
    let controller: AppController
    let appDelegate: KotaiAppDelegate

    @Environment(\.openSettings) private var openSettings

    var body: some View {
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
            appDelegate.presentDiagnostics()
        }

        Button("About Kotai…") {
            appDelegate.presentAbout()
        }

        Button("Check for Updates…") {
            controller.autoUpdates.checkForUpdates()
        }
        .disabled(!controller.autoUpdates.canCheckForUpdates)

        Divider()

        Button("Quit Kotai") {
            controller.quit()
        }
        .keyboardShortcut("q")
    }
}

enum ApplicationLaunchEnvironment {
    static func shouldStartRuntime(environment: [String: String]) -> Bool {
        environment["KOTAI_RUNNING_TESTS"] != "1"
    }
}

private struct MenuBarLabel: View {
    let controller: AppController
    let appDelegate: KotaiAppDelegate

    @Environment(\.openSettings) private var openSettings
    @State private var hasStarted = false
    @State private var hasPresentedInitialSetup = false

    var body: some View {
        Label(
            "Kotai",
            systemImage: "signpost.right.and.left"
        )
        .task {
            guard !hasStarted,
                  ApplicationLaunchEnvironment.shouldStartRuntime(
                    environment: ProcessInfo.processInfo.environment
                  )
            else {
                return
            }
            hasStarted = true
            appDelegate.configure(controller: controller)
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
