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

            Section("Cursor authentication") {
                SecureField("Proxy token", text: $proxyToken)

                HStack {
                    Button("Generate") {
                        proxyToken = controller.generateProxyToken()
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
                LabeledContent("Public URL") {
                    Text(
                        ngrokPublicURL?.absoluteString
                            ?? "Not configured"
                    )
                }
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
        .frame(width: 520, height: 450)
        .background {
            WindowTitleSetter(title: "Kotai Settings")
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
