import AppKit
import SwiftUI

struct SetupWizardView: View {
    private enum Step: Int, CaseIterable {
        case openRouter
        case ngrok
        case cursor

        var title: String {
            switch self {
            case .openRouter:
                "OpenRouter accounts"
            case .ngrok:
                "ngrok"
            case .cursor:
                "Connect clients"
            }
        }
    }

    let controller: AppController

    @State private var currentStep = Step.openRouter
    @State private var personalOpenRouterKey = ""
    @State private var workOpenRouterKey = ""
    @State private var proxyToken = ""
    @State private var ngrokAuthtoken = ""
    @State private var ngrokPublicURL: URL?
    @State private var ngrokSetupPhase: NgrokSetupPhase?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isSaving = false

    private var cursorBaseURL: String {
        baseURL(appendingPath: "cursor/v1")
    }

    private var genericBaseURL: String {
        baseURL(appendingPath: "v1")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch currentStep {
                case .openRouter:
                    openRouterStep
                case .ngrok:
                    ngrokStep
                case .cursor:
                    cursorStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)

            Divider()
            footer
        }
        .frame(width: 620, height: 520)
        .background {
            WindowTitleSetter(title: "Kotai Setup")
                .frame(width: 0, height: 0)
        }
        .task {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "signpost.right.and.left.circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up Kotai")
                        .font(.title2.bold())
                    Text("Separate personal and work OpenRouter billing.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 5)
                }
            }
        }
        .padding(28)
    }

    private var openRouterStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle(
                "Add both OpenRouter keys",
                detail: "Kotai keeps these in this Mac's Keychain and sends only the active key to OpenRouter."
            )

            SecureField("Personal OpenRouter API key", text: $personalOpenRouterKey)
                .textFieldStyle(.roundedBorder)
            SecureField("Work OpenRouter API key", text: $workOpenRouterKey)
                .textFieldStyle(.roundedBorder)

            Link(
                "Open OpenRouter",
                destination: URL(string: "https://openrouter.ai")!
            )
        }
    }

    private var ngrokStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(
                "Connect your ngrok account",
                detail: "Every free ngrok account includes a stable dev domain. Kotai starts the agent and discovers that URL automatically."
            )

            SecureField("ngrok authtoken", text: $ngrokAuthtoken)
                .textFieldStyle(.roundedBorder)

            Button {
                setupNgrok()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(
                        ngrokPublicURL == nil
                            ? "Connect ngrok"
                            : "Reconnect ngrok"
                    )
                }
            }
            .buttonStyle(WizardPrimaryButtonStyle())
            .disabled(
                isSaving
                    || ngrokAuthtoken
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
            )

            if let ngrokSetupPhase {
                Text(ngrokSetupPhase.rawValue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let ngrokPublicURL {
                Label(
                    "Connected at \(ngrokPublicURL.host() ?? ngrokPublicURL.absoluteString)",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }

            HStack {
                SecureField("Cursor proxy token", text: $proxyToken)
                    .textFieldStyle(.roundedBorder)
                Button("Generate") {
                    proxyToken = controller.generateProxyToken()
                }
            }

            Link(
                "Get your ngrok authtoken",
                destination: URL(string: "https://dashboard.ngrok.com/get-started/your-authtoken")!
            )
        }
    }

    private var cursorStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle(
                "Connect your clients",
                detail: "Use the same proxy token everywhere, then choose the base URL for your client."
            )

            copyableValue(
                title: "API key / proxy token",
                value: proxyToken
            )
            copyableValue(
                title: "Cursor base URL",
                value: cursorBaseURL
            )
            copyableValue(
                title: "Generic OpenRouter-compatible base URL",
                value: genericBaseURL
            )

            Text("In Cursor, use its OpenAI API key field and Override OpenAI Base URL. Other clients must support an OpenAI-compatible custom base URL.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if currentStep != .openRouter {
                Button("Back") {
                    moveBackward()
                }
            }

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Button(currentStep == .cursor ? "Finish" : "Continue") {
                advance()
            }
            .buttonStyle(WizardPrimaryButtonStyle())
            .disabled(isLoading || isSaving || !canContinue)
        }
        .padding(20)
    }

    private var canContinue: Bool {
        switch currentStep {
        case .openRouter:
            !personalOpenRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !workOpenRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .ngrok:
            !ngrokAuthtoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !proxyToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ngrokPublicURL != nil
        case .cursor:
            true
        }
    }

    private func stepTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }

    private func copyableValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func baseURL(appendingPath path: String) -> String {
        guard let ngrokPublicURL else {
            return "https://your-domain.ngrok-free.app/\(path)"
        }
        return ngrokPublicURL
            .appending(path: path, directoryHint: .notDirectory)
            .absoluteString
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let personalKey = controller.loadCredential(.personalOpenRouterKey)
            async let workKey = controller.loadCredential(.workOpenRouterKey)
            async let storedProxyToken = controller.loadCredential(.proxyToken)
            async let storedNgrokAuthtoken = controller.loadCredential(.ngrokAuthtoken)

            personalOpenRouterKey = try await personalKey
            workOpenRouterKey = try await workKey
            proxyToken = try await storedProxyToken
            ngrokAuthtoken = try await storedNgrokAuthtoken
            ngrokPublicURL = controller.configuredPublicURL()

            if proxyToken.isEmpty {
                proxyToken = controller.generateProxyToken()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func advance() {
        errorMessage = nil

        switch currentStep {
        case .openRouter:
            currentStep = .ngrok
        case .ngrok:
            saveCredentials()
        case .cursor:
            controller.completeSetupWizard()
        }
    }

    private func moveBackward() {
        guard let previousStep = Step(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = previousStep
    }

    private func saveCredentials() {
        isSaving = true

        Task {
            defer { isSaving = false }

            do {
                try await controller.saveCredentials(
                    personalOpenRouterKey: personalOpenRouterKey,
                    workOpenRouterKey: workOpenRouterKey,
                    proxyToken: proxyToken
                )
                currentStep = .cursor
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setupNgrok() {
        isSaving = true
        errorMessage = nil
        ngrokSetupPhase = .starting

        Task {
            defer {
                isSaving = false
                ngrokSetupPhase = nil
            }

            do {
                ngrokPublicURL = try await controller.setupNgrok(
                    authtoken: ngrokAuthtoken
                ) { phase in
                    ngrokSetupPhase = phase
                }
            } catch {
                ngrokPublicURL = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct WizardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        isEnabled
                            ? Color.accentColor
                            : Color.secondary.opacity(0.12)
                    )
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
