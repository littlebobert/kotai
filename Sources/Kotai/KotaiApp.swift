import AppKit
import SwiftUI

@main
struct KotaiApp: App {
    @NSApplicationDelegateAdaptor(KotaiAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
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
