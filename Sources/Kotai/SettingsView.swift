import SwiftUI

struct SettingsView: View {
    let controller: AppController

    @State private var personalOpenRouterKey = ""
    @State private var workOpenRouterKey = ""
    @State private var proxyToken = ""
    @State private var ngrokStaticURL = ""
    @State private var ngrokPublicURL: URL?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isConfirmingTokenRegeneration = false

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                accountsTab
                    .tabItem {
                        Label("Setups", systemImage: "person.2")
                    }

                routingTab
                    .tabItem {
                        Label("Routing", systemImage: "arrow.triangle.branch")
                    }

                connectionTab
                    .tabItem {
                        Label("ngrok", systemImage: "network")
                    }
            }
            .frame(height: 370)

            Divider()
            sharedFooter
        }
        .frame(width: 620, height: 480)
        .background {
            WindowTitleSetter(title: String(localized: "Kotai Settings"))
                .frame(width: 0, height: 0)
        }
        .task {
            await load()
        }
    }

    private var accountsTab: some View {
        tabContent {
            GroupBox("OpenRouter accounts") {
                VStack(alignment: .leading, spacing: 14) {
                    Text(
                        "Kotai keeps these in this Mac's Keychain. Every model-bearing request must select a key with a kotai/personal/ or kotai/work/ prefix."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    labeledSecureField(
                        "Personal OpenRouter API key",
                        text: $personalOpenRouterKey
                    )
                    labeledSecureField(
                        "Work OpenRouter API key",
                        text: $workOpenRouterKey
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
    }

    private var routingTab: some View {
        tabContent {
            VStack(spacing: 14) {
                GroupBox("Model routing") {
                    ModelRoutingGuide(
                        explanation: "These are examples. You must prefix every model ID with kotai/personal or kotai/work. Kotai removes the prefix before sending the request to OpenRouter."
                    )
                    .padding(6)
                }

                GroupBox("Client authentication") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "For Cursor, copy this token and paste it into the OpenAI API Key secret field."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Text("Proxy token")
                                .frame(width: 110, alignment: .trailing)
                            SecureField("Proxy token", text: $proxyToken)
                        }

                        HStack {
                            Spacer()
                            Button("Regenerate") {
                                isConfirmingTokenRegeneration = true
                            }
                            .alert(
                                "Regenerate proxy token?",
                                isPresented: $isConfirmingTokenRegeneration
                            ) {
                                Button("Cancel", role: .cancel) {}
                                Button("Regenerate", role: .destructive) {
                                    proxyToken = controller.generateProxyToken()
                                }
                            } message: {
                                Text(
                                    "Regenerating this token requires updating every connected client."
                                )
                            }
                            CopyButton(value: proxyToken, label: "Copy")
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("Static dev URL")
                            .frame(width: 110, alignment: .trailing)
                        TextField(
                            "Static dev URL",
                            text: $ngrokStaticURL,
                            prompt: Text("https://example.ngrok.app")
                        )
                    }

                    Text("Kotai uses the same static dev URL on every launch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Link(
                        "Open ngrok Domains",
                        destination: URL(string: "https://dashboard.ngrok.com/domains")!
                    )

                    Divider()

                    Text("Client base URLs")
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 16) {
                        CopyButton(
                            value: baseURL(appendingPath: "cursor/v1"),
                            label: "Copy Cursor URL",
                            reservedWidth: 170
                        )
                        CopyButton(
                            value: baseURL(appendingPath: "v1"),
                            label: "Copy generic URL",
                            reservedWidth: 170
                        )
                    }

                    Button("Reconnect ngrok…") {
                        controller.beginSetupWizard()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
    }

    private var sharedFooter: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else {
                    Text(" ")
                        .accessibilityHidden(true)
                }
            }
            .font(.caption)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)

            Button("Save") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || isSaving)
        }
        .padding(.horizontal, 20)
        .frame(height: 109)
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

    private func labeledSecureField(
        _ label: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 190, alignment: .trailing)
            SecureField(label, text: text)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let personalKey = controller.loadCredential(
                .personalOpenRouterKey
            )
            async let workKey = controller.loadCredential(.workOpenRouterKey)
            async let storedProxyToken = controller.loadCredential(.proxyToken)
            async let storedStaticURL = controller.confirmedStaticURL()

            personalOpenRouterKey = try await personalKey
            workOpenRouterKey = try await workKey
            proxyToken = try await storedProxyToken
            ngrokPublicURL = try await storedStaticURL
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

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }

            do {
                let saveResult = try await controller.saveSettings(
                    personalOpenRouterKey: personalOpenRouterKey,
                    workOpenRouterKey: workOpenRouterKey,
                    proxyToken: proxyToken,
                    staticURL: ngrokStaticURL
                )
                ngrokPublicURL = saveResult.normalizedStaticURL
                ngrokStaticURL = saveResult.normalizedStaticURL.absoluteString
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
