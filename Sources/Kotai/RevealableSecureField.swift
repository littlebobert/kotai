import SwiftUI

struct RevealableSecureField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    let prompt: LocalizedStringKey

    @State private var isRevealed = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case secure
        case revealed
    }

    private var visibilityLabel: LocalizedStringKey {
        isRevealed ? "Hide value" : "Show value"
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField(label, text: $text, prompt: Text(prompt))
                        .focused($focusedField, equals: .revealed)
                } else {
                    SecureField(label, text: $text, prompt: Text(prompt))
                        .focused($focusedField, equals: .secure)
                }
            }

            Button {
                let shouldRestoreFocus = focusedField != nil
                isRevealed.toggle()

                guard shouldRestoreFocus else {
                    return
                }

                Task { @MainActor in
                    focusedField = isRevealed ? .revealed : .secure
                }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(Text(visibilityLabel))
            .accessibilityLabel(Text(visibilityLabel))
        }
    }
}
