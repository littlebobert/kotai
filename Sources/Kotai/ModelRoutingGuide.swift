import SwiftUI

struct ModelRoutingGuide: View {
    private let explanation: LocalizedStringKey

    init(
        explanation: LocalizedStringKey = "These are examples. Every model-bearing request must prefix a real model ID with kotai/personal/ or kotai/work/; Kotai removes the prefix before sending it to OpenRouter."
    ) {
        self.explanation = explanation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                routingPattern(
                    title: "Personal model",
                    value: "kotai/personal/openai/gpt-5.6"
                )
                routingPattern(
                    title: "Work model",
                    value: "kotai/work/openai/gpt-5.6"
                )
            }
        }
    }

    private func routingPattern(
        title: LocalizedStringKey,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Spacer(minLength: 0)

                CopyButton(value: value, label: "Copy", compact: true)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
