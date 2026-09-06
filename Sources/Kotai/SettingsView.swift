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
        Form {
            Section("OpenRouter") {
                SecureField(
                    "Personal API key",
                    text: $personalOpenRouterKey
                )
                SecureField(
                    "Work API key",
                    text: $workOpenRouterKey
                )
            }

            Section("Model routing") {
                ModelRoutingGuide()
            }

            Section("Client authentication") {
                SecureField("Proxy token", text: $proxyToken)

                Text(
                    "For Cursor, copy this token and paste it into the OpenAI API Key secret field."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
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
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            proxyToken,
                            forType: .string
                        )
                    }
                    .disabled(proxyToken.isEmpty)
                }
            }

            Section("ngrok") {
                TextField(
                    "Static dev URL",
                    text: $ngrokStaticURL,
                    prompt: Text("https://example.ngrok.app")
                )

                Text("Kotai uses the same static dev URL on every launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(
                    "Open ngrok Domains",
                    destination: URL(string: "https://dashboard.ngrok.com/domains")!
                )

                HStack {
                    Button("Copy Cursor URL") {
                        copyBaseURL(appendingPath: "cursor/v1")
                    }
                    Button("Copy generic URL") {
                        copyBaseURL(appendingPath: "v1")
                    }
                }
                .disabled(ngrokPublicURL == nil)
                Button("Reconnect ngrok…") {
                    controller.beginSetupWizard()
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Save and restart") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isSaving)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .background {
            WindowTitleSetter(title: String(localized: "Kotai Settings"))
                .frame(width: 0, height: 0)
        }
        .task {
            await load()
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
            async let storedStaticURL = controller.configuredStaticURL()

            personalOpenRouterKey = try await personalKey
            workOpenRouterKey = try await workKey
            proxyToken = try await storedProxyToken
            ngrokPublicURL = try await storedStaticURL
            ngrokStaticURL = ngrokPublicURL?.absoluteString ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyBaseURL(appendingPath path: String) {
        guard let ngrokPublicURL else {
            return
        }

        let baseURL = ngrokPublicURL
            .appending(path: path, directoryHint: .notDirectory)
            .absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(baseURL, forType: .string)
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }

            do {
                let normalizedStaticURL = try await controller.saveSettings(
                    personalOpenRouterKey: personalOpenRouterKey,
                    workOpenRouterKey: workOpenRouterKey,
                    proxyToken: proxyToken,
                    staticURL: ngrokStaticURL
                )
                ngrokPublicURL = normalizedStaticURL
                ngrokStaticURL = normalizedStaticURL.absoluteString
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
