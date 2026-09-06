import AppKit
import SwiftUI

struct CopyButton: View {
    let value: String
    let label: LocalizedStringKey
    var compact = false

    @State private var isShowingConfirmation = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            copyValue()
        } label: {
            buttonLabel
                .foregroundStyle(isShowingConfirmation ? Color.green : Color.primary)
                .animation(.easeInOut(duration: 0.15), value: isShowingConfirmation)
        }
        .buttonStyle(.borderless)
        .help(isShowingConfirmation ? "Copied" : label)
        .accessibilityLabel(isShowingConfirmation ? "Copied" : label)
        .disabled(value.isEmpty)
        .onDisappear {
            resetTask?.cancel()
            resetTask = nil
        }
    }

    @ViewBuilder
    private var buttonLabel: some View {
        let displayedLabel: LocalizedStringKey = isShowingConfirmation ? "Copied" : label
        let systemImage = isShowingConfirmation ? "checkmark" : "doc.on.doc"

        if compact && !isShowingConfirmation {
            Label(displayedLabel, systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            Label(displayedLabel, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
    }

    private func copyValue() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else {
            return
        }

        resetTask?.cancel()
        isShowingConfirmation = true
        resetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.75))
            } catch {
                return
            }
            isShowingConfirmation = false
            resetTask = nil
        }
    }
}
