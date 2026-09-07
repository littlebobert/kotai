import AppKit
import SwiftUI

struct AboutView: View {
    private let versionText = AboutVersionFormatter.displayText(bundle: .main)

    var body: some View {
        VStack(spacing: 12) {
            KotaiIconView(size: 56)

            VStack(spacing: 2) {
                Text("Kotai")
                    .font(.title.bold())
                Text(versionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Text("OpenRouter chooser for Cursor, etc.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.vertical, -4)

            Link(
                "Made in Japan",
                destination: URL(string: "https://kotai.jp/")!
            )
            .font(.callout)

            Button("Report a bug…") {
                BugReporter.composeEmail()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: 320)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("About Kotai")
                    .font(.headline)
            }
        }
    }
}

enum AboutVersionFormatter {
    static func displayText(bundle: Bundle) -> String {
        displayText(
            version: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        )
    }

    static func displayText(version: String?) -> String {
        let normalizedVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedVersion, !normalizedVersion.isEmpty else {
            return String(localized: "Version unavailable")
        }
        return String(
            format: String(localized: "Version %@"),
            normalizedVersion
        )
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
