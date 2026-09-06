import AppKit
import SwiftUI

struct NativeEditingCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            NativeEditingCommandButton(
                title: "Cut",
                selector: #selector(NSText.cut(_:)),
                shortcut: "x"
            )
            NativeEditingCommandButton(
                title: "Copy",
                selector: #selector(NSText.copy(_:)),
                shortcut: "c"
            )
            NativeEditingCommandButton(
                title: "Paste",
                selector: #selector(NSText.paste(_:)),
                shortcut: "v"
            )
            NativeEditingCommandButton(
                title: "Select All",
                selector: #selector(NSText.selectAll(_:)),
                shortcut: "a"
            )
        }
    }
}

private struct NativeEditingCommandButton: View {
    let title: LocalizedStringKey
    let selector: Selector
    let shortcut: KeyEquivalent

    var body: some View {
        Button(title) {
            NSApplication.shared.sendAction(selector, to: nil, from: nil)
        }
        .keyboardShortcut(shortcut, modifiers: .command)
    }
}
