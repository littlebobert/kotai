import SwiftUI

struct SettingsView: View {
    private enum Tab: Hashable {
        case keys
        case routing
        case ngrok
    }

    let controller: AppController

    @Environment(\.openURL) private var openURL
    @State private var selectedTab = Tab.keys
    @State private var personalOpenRouterKey = ""
    @State private var workOpenRouterKey = ""
    @State private var proxyToken = ""
    @State private var ngrokStaticURL = ""
    @State private var ngrokPublicURL: URL?
    @State private var hasCompleteCredentials = false
    @State private var editingCredential: ProxyConfiguration.Credential?
    @State private var credentialDraft = ""
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var isLoading = true
    @State private var isSavingCredential = false
    @State private var isRestartingNgrok = false
    @State private var isConfirmingTokenRegeneration = false
    @State private var savedMessageTask: Task<Void, Never>?
    @FocusState private var isNgrokStaticURLFocused: Bool

    private var connectionDraft: SettingsConnectionDraft {
        SettingsConnectionDraft(
            rawValue: ngrokStaticURL,
            confirmedURL: ngrokPublicURL,
            runtimeStatus: controller.runtimeStatus,
            hasCompleteCredentials: hasCompleteCredentials
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                accountsTab
                    .tag(Tab.keys)
                    .tabItem {
                        Label("Keys", systemImage: "person.2")
                    }

                routingTab
                    .tag(Tab.routing)
                    .tabItem {
                        Label("Routing", systemImage: "arrow.triangle.branch")
                    }

                connectionTab
                    .tag(Tab.ngrok)
                    .tabItem {
                        Label("ngrok", systemImage: "network")
                    }
            }
            .frame(height: 415)

            Divider()
            statusFooter
        }
        .frame(width: 620, height: 480)
        .background {
            WindowTitleSetter(title: String(localized: "Kotai Settings"))
                .frame(width: 0, height: 0)
        }
        .overlay {
            settingsTabKeyboardShortcuts
        }
        .task {
            await load()
        }
        .onDisappear {
            savedMessageTask?.cancel()
        }
    }

    private var settingsTabKeyboardShortcuts: some View {
        Group {
            Button("Show Keys") {
                selectedTab = .keys
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Show Routing") {
                selectedTab = .routing
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Show ngrok") {
                selectedTab = .ngrok
            }
            .keyboardShortcut("3", modifiers: .command)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var accountsTab: some View {
        tabContent {
            GroupBox("OpenRouter setups") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "Kotai keeps these in this Mac's Keychain. Every model-bearing request must select a key with a kotai/personal/ or kotai/work/ prefix."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    credentialRow(
                        credential: .personalOpenRouterKey,
                        label: "Personal OpenRouter API key",
                        value: personalOpenRouterKey,
                        prompt: "Paste your personal OpenRouter API key"
                    )
                    credentialRow(
                        credential: .workOpenRouterKey,
                        label: "Work OpenRouter API key",
                        value: workOpenRouterKey,
                        prompt: "Paste your work OpenRouter API key"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
    }

    private var routingTab: some View {
        tabContent {
            VStack(spacing: 12) {
                GroupBox("Model routing") {
                    ModelRoutingGuide(
                        explanation: "These are examples. You must prefix every model ID with kotai/personal or kotai/work. Kotai removes the prefix before sending the request to OpenRouter."
                    )
                    .padding(6)
                }

                GroupBox("Client authentication") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "For Cursor, copy this token and paste it into the OpenAI API Key secret field."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        credentialRow(
                            credential: .proxyToken,
                            label: "Proxy token",
                            value: proxyToken,
                            prompt: "Paste your proxy token"
                        )

                        HStack {
                            CopyButton(value: proxyToken, label: "Copy")
                            Button("Regenerate") {
                                isConfirmingTokenRegeneration = true
                            }
                            .alert(
                                "Regenerate proxy token?",
                                isPresented: $isConfirmingTokenRegeneration
                            ) {
                                Button("Cancel", role: .cancel) {}
                                Button("Regenerate", role: .destructive) {
                                    regenerateProxyToken()
                                }
                            } message: {
                                Text(
                                    "Regenerating this token requires updating every connected client."
                                )
                            }
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }
        }
    }

    private var connectionTab: some View {
        tabContent {
            GroupBox("ngrok connection") {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Static dev URL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "Static dev URL",
                            text: $ngrokStaticURL,
                            prompt: StaticURLPrompt.fieldPrompt
                        )
                        .focused($isNgrokStaticURLFocused)
                        .onChange(of: isNgrokStaticURLFocused) { _, isFocused in
                            if !isFocused {
                                normalizeNgrokStaticURLDraft()
                            }
                        }
                        .onSubmit {
                            restartNgrokIfAvailable()
                        }

                        Text("For example: your-static-ngrok-identifier.ngrok-free.dev")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if let validationError = connectionDraft.validationError {
                            Text(validationError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Restart ngrok") {
                            restartNgrok()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!connectionDraft.canRestartNgrok || isRestartingNgrok)

                        if isRestartingNgrok {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Button("Open ngrok Domains") {
                            openURL(
                                URL(string: "https://dashboard.ngrok.com/domains")!
                            )
                        }
                        Spacer()
                    }

                    Divider()

                    Text("Client base URLs")
                        .font(.callout.weight(.semibold))
                    CopyButton(
                        value: baseURL(appendingPath: "cursor/v1"),
                        label: "Copy Cursor URL",
                        reservedWidth: 170,
                        reservedAlignment: .leading
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CopyButton(
                        value: baseURL(appendingPath: "v1"),
                        label: "Copy generic URL",
                        reservedWidth: 170,
                        reservedAlignment: .leading
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Start Setup Wizard again…") {
                        controller.beginSetupWizard()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
    }

    private var statusFooter: some View {
        Group {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if let savedMessage {
                Text(savedMessage)
                    .foregroundStyle(.secondary)
            } else {
                Text(" ")
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 20)
        .frame(height: 65)
    }

    private func tabContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(20)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
    }

    @ViewBuilder
    private func credentialRow(
        credential: ProxyConfiguration.Credential,
        label: LocalizedStringKey,
        value: String,
        prompt: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if editingCredential == credential {
                VStack(alignment: .leading, spacing: 7) {
                    RevealableSecureField(
                        label: label,
                        text: $credentialDraft,
                        prompt: prompt
                    )
                    .onSubmit {
                        saveEditingCredential(credential)
                    }

                    HStack(spacing: 8) {
                        Button("Done") {
                            saveEditingCredential(credential)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSavingCredential)
                        Button("Cancel") {
                            cancelEditingCredential()
                        }
                        .disabled(isSavingCredential)
                        Spacer()
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Text(SecretSummary(value: value).displayValue)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(value.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Button("Edit") {
                        editingCredential = credential
                        credentialDraft = value
                        clearFeedback()
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let personalKey = controller.loadCredential(.personalOpenRouterKey)
            async let workKey = controller.loadCredential(.workOpenRouterKey)
            async let storedProxyToken = controller.loadCredential(.proxyToken)
            async let storedStaticURL = controller.confirmedStaticURL()
            async let credentialsComplete = controller.hasCompleteSettingsCredentials()

            personalOpenRouterKey = try await personalKey
            workOpenRouterKey = try await workKey
            proxyToken = try await storedProxyToken
            ngrokPublicURL = try await storedStaticURL
            hasCompleteCredentials = try await credentialsComplete
            ngrokStaticURL = ngrokPublicURL?.absoluteString ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func baseURL(appendingPath path: String) -> String {
        guard let ngrokPublicURL else {
            return ""
        }
        return ngrokPublicURL
            .appending(path: path, directoryHint: .notDirectory)
            .absoluteString
    }

    private func saveEditingCredential(
        _ credential: ProxyConfiguration.Credential
    ) {
        guard editingCredential == credential, !isSavingCredential else {
            return
        }
        isSavingCredential = true
        clearFeedback()

        Task {
            defer { isSavingCredential = false }
            do {
                let savedValue = try await controller.updateCredential(
                    credential,
                    value: credentialDraft
                )
                setCredential(savedValue, for: credential)
                editingCredential = nil
                credentialDraft = ""
                hasCompleteCredentials = try await controller.hasCompleteSettingsCredentials()
                showSaved()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelEditingCredential() {
        editingCredential = nil
        credentialDraft = ""
        clearFeedback()
    }

    private func setCredential(
        _ value: String,
        for credential: ProxyConfiguration.Credential
    ) {
        switch credential {
        case .personalOpenRouterKey:
            personalOpenRouterKey = value
        case .workOpenRouterKey:
            workOpenRouterKey = value
        case .proxyToken:
            proxyToken = value
        case .ngrokAuthtoken, .ngrokStaticURL:
            break
        }
    }

    private func regenerateProxyToken() {
        clearFeedback()
        Task {
            do {
                proxyToken = try await controller.regenerateAndPersistProxyToken()
                if editingCredential == .proxyToken {
                    editingCredential = nil
                    credentialDraft = ""
                }
                hasCompleteCredentials = try await controller.hasCompleteSettingsCredentials()
                showSaved()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func normalizeNgrokStaticURLDraft() {
        guard let normalizedURL = connectionDraft.normalizedURL else {
            return
        }
        ngrokStaticURL = normalizedURL.absoluteString
    }

    private func restartNgrokIfAvailable() {
        guard connectionDraft.canRestartNgrok else {
            return
        }
        restartNgrok()
    }

    private func restartNgrok() {
        guard connectionDraft.canRestartNgrok, !isRestartingNgrok else {
            return
        }
        isRestartingNgrok = true
        clearFeedback()

        Task {
            defer { isRestartingNgrok = false }
            do {
                let normalizedURL = try await controller.restartWithStaticURL(
                    ngrokStaticURL
                )
                ngrokPublicURL = normalizedURL
                ngrokStaticURL = normalizedURL.absoluteString
                showSaved()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearFeedback() {
        errorMessage = nil
        savedMessage = nil
        savedMessageTask?.cancel()
        savedMessageTask = nil
    }

    private func showSaved() {
        clearFeedback()
        savedMessage = String(localized: "Saved")
        savedMessageTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.75))
            } catch {
                return
            }
            savedMessage = nil
            savedMessageTask = nil
        }
    }
}
