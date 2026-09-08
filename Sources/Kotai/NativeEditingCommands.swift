import AppKit
import SwiftUI

struct KotaiCommands: Commands {
    let controller: AppController
    let appDelegate: KotaiAppDelegate

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Kotai") {
                appDelegate.presentAbout()
            }

            Button {
                controller.autoUpdates.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
            }
            .disabled(!controller.autoUpdates.canCheckForUpdates)
        }

        CommandGroup(replacing: .appSettings) {
            Button {
                appDelegate.presentSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                appDelegate.presentSetup()
            } label: {
                Label("Run Setup…", systemImage: "wand.and.stars")
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
            Button {
                appDelegate.presentDiagnostics()
            } label: {
                Label("Diagnostics", systemImage: "stethoscope")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Button {
                appDelegate.presentUsageStatistics()
            } label: {
                Label("Usage Statistics", systemImage: "chart.xyaxis.line")
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Link(destination: URL(string: "https://kotai.jp/")!) {
                Label("Kotai Website", systemImage: "globe")
            }
            Button {
                BugReporter.composeEmail()
            } label: {
                Label("Report a Bug…", systemImage: "ladybug")
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
