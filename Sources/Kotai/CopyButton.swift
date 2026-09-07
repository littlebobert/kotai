import AppKit
import SwiftUI

struct CopyButton: View {
    let value: String
    let label: LocalizedStringKey
    var compact = false
    var reservedWidth: CGFloat? = nil
    var reservedAlignment: Alignment = .center

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
        .frame(width: reservedWidth, alignment: reservedAlignment)
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
        if compact {
            ZStack(alignment: reservedAlignment) {
                Label("Copied", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .hidden()
                Image(systemName: "doc.on.doc")
                    .opacity(isShowingConfirmation ? 0 : 1)
                Label("Copied", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .opacity(isShowingConfirmation ? 1 : 0)
            }
        } else {
            ZStack(alignment: reservedAlignment) {
                Label(label, systemImage: "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .hidden()
                Label("Copied", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .hidden()
                Label(label, systemImage: "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .opacity(isShowingConfirmation ? 0 : 1)
                Label("Copied", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .opacity(isShowingConfirmation ? 1 : 0)
            }
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
