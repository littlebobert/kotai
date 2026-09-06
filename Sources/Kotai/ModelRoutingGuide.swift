import AppKit
import SwiftUI

struct ModelRoutingGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Use personal and work projects at the same time. Prefix any model ID with one of these patterns; Kotai removes the prefix before sending to OpenRouter. Unprefixed model IDs use the menu-bar default."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                routingPattern(
                    title: "Personal model prefix",
                    value: "kotai/personal/<model-id>"
                )
                routingPattern(
                    title: "Work model prefix",
                    value: "kotai/work/<model-id>"
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
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
