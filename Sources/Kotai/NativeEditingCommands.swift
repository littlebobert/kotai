import AppKit
import SwiftUI

struct KotaiCommands: Commands {
    let controller: AppController
    let appDelegate: KotaiAppDelegate

    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Kotai") {
                appDelegate.presentAbout()
            }

            Button("Check for Updates…") {
                controller.autoUpdates.checkForUpdates()
            }
            .disabled(!controller.autoUpdates.canCheckForUpdates)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                controller.completeSetupWizard()
                presentSettingsWindow(openSettings: openSettings)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Run Setup…") {
                controller.beginSetupWizard()
                presentSettingsWindow(openSettings: openSettings)
            }
        }

        CommandGroup(replacing: .pasteboard) {
            NativeResponderCommand(
                title: "Cut",
                selector: #selector(NSText.cut(_:)),
                shortcut: "x"
            )
            NativeResponderCommand(
                title: "Copy",
                selector: #selector(NSText.copy(_:)),
                shortcut: "c"
            )
            NativeResponderCommand(
                title: "Paste",
                selector: #selector(NSText.paste(_:)),
                shortcut: "v"
            )
            NativeResponderCommand(
                title: "Select All",
                selector: #selector(NSText.selectAll(_:)),
                shortcut: "a"
            )
        }

        CommandGroup(after: .textEditing) {
            Divider()
            NativeResponderCommand(
                title: "Find…",
                selector: #selector(NSTextView.performFindPanelAction(_:)),
                shortcut: "f",
                tag: NSFindPanelAction.showFindPanel.rawValue
            )
            NativeResponderCommand(
                title: "Find Next",
                selector: #selector(NSTextView.performFindPanelAction(_:)),
                shortcut: "g",
                tag: NSFindPanelAction.next.rawValue
            )
            NativeResponderCommand(
                title: "Find Previous",
                selector: #selector(NSTextView.performFindPanelAction(_:)),
                shortcut: "g",
                modifiers: [.command, .shift],
                tag: NSFindPanelAction.previous.rawValue
            )
        }

        CommandGroup(after: .windowList) {
            Button("Diagnostics") {
                appDelegate.presentDiagnostics()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Link("Kotai Website", destination: URL(string: "https://kotai.jp/")!)
            Button("Report a Bug…") {
                BugReporter.composeEmail()
            }
        }
    }
}

private struct NativeResponderCommand: View {
    let title: LocalizedStringKey
    let selector: Selector
    let shortcut: KeyEquivalent
    var modifiers: EventModifiers = .command
    var tag: UInt? = nil

    var body: some View {
        Button(title) {
            let sender = tag.map { commandTag in
                let menuItem = NSMenuItem()
                menuItem.tag = Int(commandTag)
                return menuItem
            }
            NSApplication.shared.sendAction(selector, to: nil, from: sender)
        }
        .keyboardShortcut(shortcut, modifiers: modifiers)
    }
}
