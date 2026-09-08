import AppKit
import SwiftUI

struct SetupWizardView: View {
    private enum Step: Int, CaseIterable {
        case upgrade
        case personal
        case work
        case ngrok
        case cursor
        case modelRouting
        case support

        var title: String {
            switch self {
            case .upgrade:
                String(localized: "What’s new")
            case .personal:
                String(localized: "Personal setup")
            case .work:
                String(localized: "Work setup")
            case .ngrok:
                "ngrok"
            case .cursor:
                String(localized: "Connect clients")
            case .modelRouting:
                String(localized: "Model routing")
            case .support:
                String(localized: "Support")
            }
        }
    }

    let controller: AppController
    let onFinished: () -> Void

    @State private var currentStep = Step.personal
    @State private var isManagedUpgrade = false
    @State private var personalStagedAccount: StagedManagedAccount?
    @State private var workStagedAccount: StagedManagedAccount?
    @State private var hasCommittedManagedAccounts = false
    @State private var personalOpenRouterKey = ""
    @State private var workOpenRouterKey = ""
    @State private var proxyToken = ""
    @State private var ngrokAuthtoken = ""
    @State private var storedNgrokAuthtoken = ""
    @State private var ngrokStaticURL = ""
    @State private var ngrokPublicURL: URL?
    @State private var ngrokSetupPhase: NgrokSetupPhase?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var credentialLoadFailed = false
    @FocusState private var isNgrokStaticURLFocused: Bool

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

            if credentialLoadFailed, let errorMessage {
                keychainAccessError(errorMessage)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
            }

            if currentStep == .cursor {
                cursorStep
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(28)
            } else if currentStep == .personal {
                ManagedAccountSetupView(mode: .personal, controller: controller) { stagedAccount in
                    personalStagedAccount = stagedAccount
                    currentStep = .work
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            } else if currentStep == .work {
                ManagedAccountSetupView(mode: .work, controller: controller) { stagedAccount in
                    workStagedAccount = stagedAccount
                    currentStep = .ngrok
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            } else {
                ScrollView {
                    Group {
                        switch currentStep {
                        case .upgrade: upgradeStep
                        case .ngrok: ngrokStep
                        case .modelRouting: modelRoutingStep
                        case .support: supportStep
                        case .personal, .work, .cursor: EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if currentStep != .personal && currentStep != .work {
                Divider()
                footer
            }
        }
        .frame(width: 620, height: currentStep == .cursor ? 640 : 520)
        .background {
            WindowTitleSetter(title: String(localized: "Kotai Setup"))
                .frame(width: 0, height: 0)
        }
        .task {
            await load()
        }
        .onDisappear {
            guard !hasCommittedManagedAccounts else { return }
            let stagedAccounts = [personalStagedAccount, workStagedAccount].compactMap { $0 }
            Task { await controller.discardManagedAccounts(stagedAccounts) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                KotaiIconView(size: 40)

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

    private var upgradeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 42)).foregroundStyle(.tint)
            stepTitle(
                "Kotai can now help track your spending",
                detail: "Your previous setup is still available while you create isolated Personal and Work workspaces, keys, and OpenAI BYOK connections. Kotai switches to the new setup only after each side succeeds."
            )
        }
    }

    private var ngrokStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(
                "Connect your ngrok account",
                detail: "Paste both your authtoken and assigned static dev URL. Kotai reuses this URL every launch."
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("ngrok authtoken")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                RevealableSecureField(
                    label: "ngrok authtoken",
                    text: $ngrokAuthtoken,
                    prompt: ngrokAuthtokenPrompt
                )
                .textFieldStyle(.roundedBorder)
                underlinedLink(
                    "Get your ngrok authtoken",
                    destination: URL(string: "https://dashboard.ngrok.com/get-started/your-authtoken")!
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ngrok static domain")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "ngrok static domain",
                    text: $ngrokStaticURL,
                    prompt: StaticURLPrompt.fieldPrompt
                )
                .textFieldStyle(.roundedBorder)
                .focused($isNgrokStaticURLFocused)
                .onChange(of: isNgrokStaticURLFocused) { _, isFocused in
                    if !isFocused {
                        normalizeNgrokStaticURLDraft()
                    }
                }
                Text("Example: your-free-static-domain.ngrok-free.dev")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                underlinedLink(
                    "Get your ngrok static domain",
                    destination: URL(string: "https://dashboard.ngrok.com/domains")!
                )
            }

            if let ngrokSetupPhase {
                Text(ngrokSetupPhase.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let ngrokPublicURL {
                Label(
                    "Connected at \(ngrokPublicURL.host() ?? ngrokPublicURL.absoluteString)",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }

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

    private var modelRoutingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle(
                "Route models to each account",
                detail: "Use a model prefix to choose personal or work billing for each request."
            )
            ModelRoutingGuide()
        }
    }

    private var supportStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Support").font(.title3.bold())
            HStack(spacing: 4) {
                Text("If you have issues or questions,")
                Button("report a bug.") { BugReporter.composeEmail() }
                    .buttonStyle(.link)
            }
        }
    }

    private var footer: some View {
        ZStack {
            HStack {
                if currentStep != (isManagedUpgrade ? .upgrade : .personal)
                    && currentStep != .personal && currentStep != .work {
                    Button("Back") { moveBackward() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isSaving)
                }

                Spacer()

                if currentStep != .personal && currentStep != .work {
                    Button {
                        advance()
                    } label: {
                        HStack(spacing: 6) {
                            if currentStep == .ngrok, isSaving {
                                ProgressView().controlSize(.small)
                            }
                            Text(continueButtonTitle)
                        }
                        .frame(minWidth: 72)
                    }
                    .buttonStyle(WizardPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLoading || isSaving || !canContinue)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 110)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var continueButtonTitle: String {
        if currentStep == .support {
            return String(localized: "Finish")
        }
        if currentStep == .ngrok, isSaving {
            return String(localized: "Connecting…")
        }
        return String(localized: "Continue")
    }

    private var ngrokAuthtokenPrompt: LocalizedStringKey {
        storedNgrokAuthtoken.isEmpty
            ? "Paste your ngrok authtoken"
            : "Saved authtoken"
    }

    private var effectiveNgrokAuthtoken: String {
        let enteredAuthtoken = ngrokAuthtoken.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return enteredAuthtoken.isEmpty ? storedNgrokAuthtoken : enteredAuthtoken
    }

    private var canContinue: Bool {
        guard !credentialLoadFailed else {
            return false
        }
        switch currentStep {
        case .upgrade, .personal, .work:
            return true
        case .ngrok:
            return !effectiveNgrokAuthtoken.isEmpty
                && !ngrokStaticURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .cursor, .modelRouting:
            return true
        case .support:
            return personalStagedAccount != nil && workStagedAccount != nil
        }
    }

    private func keychainAccessError(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "key.slash.fill")
        }
        .font(.callout)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func stepTitle(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }

    private func labeledSecureField(
        _ label: LocalizedStringKey,
        prompt: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            SecureField(label, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func underlinedLink(
        _ label: LocalizedStringKey,
        destination: URL
    ) -> some View {
        Link(label, destination: destination)
            .underline()
    }

    private func copyableValue(
        title: LocalizedStringKey,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                CopyButton(value: value, label: "Copy", compact: true)
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
            async let storedNgrokAuthtokenTask = controller.loadCredential(.ngrokAuthtoken)
            async let confirmedStaticURL = controller.confirmedStaticURL()
            async let suggestedStaticURL = controller.setupStaticURLSuggestion()

            let loadedPersonalKey = try await personalKey
            let loadedWorkKey = try await workKey
            let loadedProxyToken = try await storedProxyToken
            let loadedNgrokAuthtoken = try await storedNgrokAuthtokenTask
            let confirmedURL = try await confirmedStaticURL
            let suggestionURL = try await suggestedStaticURL

            personalOpenRouterKey = loadedPersonalKey
            workOpenRouterKey = loadedWorkKey
            proxyToken = loadedProxyToken
            storedNgrokAuthtoken = loadedNgrokAuthtoken
            ngrokAuthtoken = ""
            ngrokStaticURL = (confirmedURL ?? suggestionURL)?.absoluteString ?? ""
            ngrokPublicURL = confirmedURL
            isManagedUpgrade = await controller.requiresManagedSetupUpgrade()
            currentStep = isManagedUpgrade ? .upgrade : .personal
        } catch {
            clearLoadedValues()
            credentialLoadFailed = true
            errorMessage = error.localizedDescription
        }
    }

    private func clearLoadedValues() {
        personalOpenRouterKey = ""
        workOpenRouterKey = ""
        proxyToken = ""
        ngrokAuthtoken = ""
        storedNgrokAuthtoken = ""
        ngrokStaticURL = ""
        ngrokPublicURL = nil
    }

    private func advance() {
        errorMessage = nil

        switch currentStep {
        case .upgrade:
            currentStep = .personal
        case .personal, .work:
            break
        case .ngrok:
            setupNgrok()
        case .cursor:
            currentStep = .modelRouting
        case .modelRouting:
            currentStep = .support
            let completionSound = NSSound(named: NSSound.Name("Crystal"))
                ?? NSSound(named: NSSound.Name("Bottle"))
            completionSound?.play()
        case .support:
            finishSetup()
        }
    }

    private func finishSetup() {
        guard let personalStagedAccount, let workStagedAccount, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await controller.commitManagedAccounts([personalStagedAccount, workStagedAccount])
                hasCommittedManagedAccounts = true
                controller.recordSuccessfulSetup()
                controller.completeSetupWizard()
                onFinished()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func moveBackward() {
        guard let previousStep = Step(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = previousStep
    }

    private func normalizeNgrokStaticURLDraft() {
        guard let normalizedURL = try? NgrokStaticURL(ngrokStaticURL) else {
            return
        }
        ngrokStaticURL = normalizedURL.absoluteString
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
                let authtoken = effectiveNgrokAuthtoken
                let setupResult = try await controller.setupNgrok(
                    authtoken: authtoken,
                    staticURL: ngrokStaticURL
                ) { phase in
                    ngrokSetupPhase = phase
                }
                let normalizedStaticURL = setupResult.publicURL.absoluteString
                try await controller.saveSetupCredentials(
                    personalOpenRouterKey: personalOpenRouterKey,
                    workOpenRouterKey: workOpenRouterKey,
                    proxyToken: setupResult.proxyToken,
                    ngrokAuthtoken: authtoken,
                    ngrokStaticURL: normalizedStaticURL
                )
                ngrokPublicURL = setupResult.publicURL
                ngrokStaticURL = normalizedStaticURL
                proxyToken = setupResult.proxyToken
                currentStep = .cursor
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
