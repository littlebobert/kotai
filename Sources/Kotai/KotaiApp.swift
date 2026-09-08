import AppKit
import SwiftUI

@main
struct KotaiApp: App {
    @NSApplicationDelegateAdaptor(KotaiAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            if appDelegate.controller.shouldShowSetupWizard {
                SetupWizardView(controller: appDelegate.controller)
            } else {
                SettingsView(controller: appDelegate.controller)
            }
        }
        .commands {
            KotaiCommands(
                controller: appDelegate.controller,
                appDelegate: appDelegate
            )
        }
    }
}

enum ApplicationLaunchEnvironment {
    static func shouldStartRuntime(environment: [String: String]) -> Bool {
        environment["KOTAI_RUNNING_TESTS"] != "1"
    }
}
