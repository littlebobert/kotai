import AppKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "signpost.right.and.left")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.tint)

            Text("Kotai")
                .font(.largeTitle.bold())

            Text("OpenRouter chooser for Cursor, etc.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Made in Japan")
                .font(.callout)

            Button("Report a bug…") {
                BugReporter.composeEmail()
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 320)
    }
}

@MainActor
enum BugReporter {
    static func composeEmail() {
        KotaiLogger.shared.info("Opening bug report email composer")

        guard let service = NSSharingService(named: .composeEmail) else {
            let alert = NSAlert()
            alert.messageText = String(localized: "No email app is available")
            alert.informativeText = String(
                localized: "Email justin.garcia@gmail.com and attach the Kotai log files."
            )
            alert.runModal()
            return
        }

        service.recipients = ["justin.garcia@gmail.com"]
        service.subject = String(localized: "Kotai bug report")
        let recentDiagnostics = KotaiLogger.shared.recentLogText(maxLines: 100)
        let body = """
        \(String(localized: "Please describe what happened:"))


        \(String(localized: "Kotai diagnostic logs are attached. They exclude API keys, authentication tokens, prompts, and response bodies."))

        \(String(localized: "Recent diagnostics:"))
        \(recentDiagnostics)
        """
        var items: [Any] = [body]
        if let diagnosticURL = KotaiLogger.shared.makeDiagnosticAttachment() {
            items.append(diagnosticURL)
        }
        service.perform(withItems: items)
    }
}
