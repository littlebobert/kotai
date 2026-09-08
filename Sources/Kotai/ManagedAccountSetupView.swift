import SwiftUI

struct ManagedAccountSetupView: View {
    private enum Phase { case credentials, resources }
    private static let newWorkspaceID = "__new_workspace__"

    let mode: AccountMode
    let controller: AppController
    let onProvisioned: (StagedManagedAccount) -> Void

    @State private var phase = Phase.credentials
    @State private var fieldIdentity = UUID()
    @State private var openRouterManagementKey = ""
    @State private var openAIAdminKey = ""
    @State private var workspaces: [OpenRouterWorkspace] = []
    @State private var projects: [OpenAIProject] = []
    @State private var selectedWorkspaceID = ""
    @State private var selectedProjectID = ""
    @State private var newWorkspaceName = ""
    @State private var isLoading = false
    @State private var isProvisioning = false
    @State private var errorMessage: String?

    private var accountName: String { mode == .personal ? "Personal" : "Work" }
    private var selectedWorkspace: OpenRouterWorkspace? { workspaces.first { $0.id == selectedWorkspaceID } }
    private var selectedProject: OpenAIProject? { projects.first { $0.id == selectedProjectID } }
    private var canValidate: Bool {
        !openRouterManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (mode == .work || !openAIAdminKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !isLoading
    }
    private var canProvision: Bool {
        selectedWorkspace != nil
            && (mode == .work || selectedProject != nil)
            && !isProvisioning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .credentials: credentialsPage
            case .resources: resourcesPage
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            Spacer(minLength: 12)
            navigationControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            openRouterManagementKey = ""
            openAIAdminKey = ""
            fieldIdentity = UUID()
        }
    }

    private var credentialsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect \(accountName)").font(.title3.bold())
            Text(mode == .personal
                ? "Enter administrative keys. Kotai validates them now and saves them only after the entire setup wizard finishes."
                : "Enter an OpenRouter Management key. Work setups use OpenRouter credits and do not require an OpenAI Admin key.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            secureField("OpenRouter Management key", text: $openRouterManagementKey)
            Link("Create an OpenRouter Management key", destination: URL(string: "https://openrouter.ai/settings/management-keys")!)

            if mode == .personal {
                secureField("OpenAI Admin key", text: $openAIAdminKey)
                Link("Create an OpenAI Admin key", destination: URL(string: "https://platform.openai.com/settings/organization/admin-keys")!)
            }

        }
    }

    private var resourcesPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose \(accountName) resources").font(.title3.bold())
            Text("Choose where Kotai should create its isolated OpenRouter key\(mode == .personal ? " and OpenAI BYOK service account" : "").")
                .foregroundStyle(.secondary)

            Picker("OpenRouter workspace:", selection: $selectedWorkspaceID) {
                ForEach(workspaces) { Text($0.name).tag($0.id) }
                Divider()
                Text("New…").tag(Self.newWorkspaceID)
            }

            if selectedWorkspaceID == Self.newWorkspaceID {
                HStack {
                    TextField("New workspace name", text: $newWorkspaceName)
                    Button("Create Workspace") { createWorkspace() }
                        .disabled(newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }

            if mode == .personal {
                Picker("OpenAI project:", selection: $selectedProjectID) {
                    ForEach(projects) { Text($0.name).tag($0.id) }
                }
            } else if let selectedWorkspace {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Optional: add your own OpenAI API key to this workspace. Without BYOK, Work uses OpenRouter credits.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link(
                        "Set up OpenAI BYOK in this workspace",
                        destination: URL(
                            string: "https://openrouter.ai/workspaces/\(selectedWorkspace.slug)/byok/openai"
                        )!
                    )
                }
            }

        }
    }

    private var navigationControls: some View {
        HStack {
            if phase == .resources {
                Button("Back") { phase = .credentials }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if isLoading || isProvisioning { ProgressView().controlSize(.small) }
            switch phase {
            case .credentials:
                Button("Continue") { validateCredentials() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canValidate)
            case .resources:
                Button(isProvisioning ? "Creating setup…" : "Create \(accountName) setup") { provision() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canProvision)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func secureField(_ label: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            RevealableSecureField(
                label: label,
                text: text,
                prompt: "Paste key"
            )
            .id("\(fieldIdentity.uuidString)-\(String(describing: label))")
            .textFieldStyle(.roundedBorder)
            .privacySensitive()
        }
    }

    private func validateCredentials() {
        isLoading = true; errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                async let loadedWorkspaces = controller.openRouterWorkspaces(managementKey: openRouterManagementKey)
                if mode == .personal {
                    async let loadedProjects = controller.openAIProjects(adminKey: openAIAdminKey)
                    workspaces = try await loadedWorkspaces
                    projects = try await loadedProjects
                    guard !projects.isEmpty else { throw AdministrationAPIError.forbidden("No active OpenAI projects are available.") }
                    selectedProjectID = projects[0].id
                } else {
                    workspaces = try await loadedWorkspaces
                }
                selectedWorkspaceID = workspaces.first?.id ?? Self.newWorkspaceID
                phase = .resources
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func createWorkspace() {
        isLoading = true; errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                let workspace = try await controller.createOpenRouterWorkspace(
                    name: newWorkspaceName,
                    managementKey: openRouterManagementKey
                )
                workspaces.append(workspace)
                selectedWorkspaceID = workspace.id
                newWorkspaceName = ""
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func provision() {
        guard let selectedWorkspace else { return }
        isProvisioning = true; errorMessage = nil
        Task {
            defer { isProvisioning = false }
            do {
                let stagedAccount = try await controller.stageManagedAccount(
                    ManagedAccountDraft(
                        accountMode: mode,
                        openRouterManagementKey: openRouterManagementKey,
                        openAIAdminKey: mode == .personal ? openAIAdminKey : nil,
                        openRouterWorkspace: selectedWorkspace,
                        openAIProject: mode == .personal ? selectedProject : nil
                    )
                )
                onProvisioned(stagedAccount)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
