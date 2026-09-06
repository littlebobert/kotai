import SwiftUI

struct SettingsView: View {
    let controller: AppController

    @State private var personalOpenRouterKey = ""
    @State private var workOpenRouterKey = ""
    @State private var proxyToken = ""
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Public URL")
                    Text(
                        ngrokPublicURL?.absoluteString
                            ?? String(localized: "Not configured")
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)
                }
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 520)
        .scrollDisabled(true)
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

            personalOpenRouterKey = try await personalKey
            workOpenRouterKey = try await workKey
            proxyToken = try await storedProxyToken
            ngrokPublicURL = controller.configuredPublicURL()
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
                try await controller.saveCredentials(
                    personalOpenRouterKey: personalOpenRouterKey,
                    workOpenRouterKey: workOpenRouterKey,
                    proxyToken: proxyToken
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
