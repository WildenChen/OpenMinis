import SwiftUI

/// External Agent Backend settings surfaced from the normal Providers screen.
///
/// MVP surface (issue #4): one OpenClaw backend with backend URL, target agent
/// ID, Gateway credential (status only — the secret is never redisplayed), and
/// an explicit Active toggle. No model overrides or arbitrary headers.
///
/// Persistence:
///   - URL + agent ID → `OpenClawBackendConfigStore` (UserDefaults)
///   - Gateway credential → `OpenClawBackendCredentialStore` (Keychain)
///   - Active backend → `AgentBackendConfigStore.setActive(...)`
struct ExternalAgentBackendSettingsView: View {
    @State private var baseURLText = ""
    @State private var agentIDText = ""
    @State private var credentialConfigured = false
    @State private var active = false

    @State private var showCredentialInput = false
    @State private var credentialInputText = ""
    @State private var showRemoveConfirm = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Backend URL"), text: $baseURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Backend URL")
            } footer: {
                Text("OpenClaw Gateway base URL, e.g. http://127.0.0.1:18789")
            }

            Section {
                TextField(String(localized: "Agent ID"), text: $agentIDText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Agent")
            } footer: {
                Text("Target OpenClaw agent (e.g. yujie). Leave empty to use the Gateway's default agent.")
            }

            Section {
                HStack {
                    Image(systemName: credentialConfigured ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(credentialConfigured ? Color.green : Color.secondary)
                    Text(credentialConfigured
                         ? String(localized: "Credential configured")
                         : String(localized: "No credential configured"))
                        .foregroundStyle(credentialConfigured ? .primary : .secondary)
                }
                if credentialConfigured {
                    Button("Replace Credential") {
                        credentialInputText = ""
                        showCredentialInput = true
                    }
                    Button("Remove Credential", role: .destructive) {
                        showRemoveConfirm = true
                    }
                } else {
                    Button("Enter Credential") {
                        credentialInputText = ""
                        showCredentialInput = true
                    }
                }
            } header: {
                Text("Gateway Credential")
            } footer: {
                Text("The Gateway bearer token is stored in the iOS Keychain and is never shown again after saving.")
            }

            Section {
                Toggle(isOn: $active) {
                    Label {
                        Text(String(localized: "Active backend"))
                    } icon: {
                        Image(systemName: "bolt")
                    }
                }
                .onChange(of: active) { _, isOn in
                    handleActiveChange(isOn)
                }
            } footer: {
                if active {
                    if credentialConfigured {
                        Text("Chat now routes through the OpenClaw backend. Deactivate to switch back to normal providers.")
                    } else {
                        Text("Chat routes through OpenClaw, but no Gateway credential is configured — requests will fail auth until one is added.")
                    }
                } else {
                    Text("Activating makes the external backend the only agent brain. Only one backend can be active at a time.")
                }
            }
        }
        .navigationTitle("External Agent Backend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveSettings() }
            }
        }
        .sheet(isPresented: $showCredentialInput) {
            NavigationStack {
                Form {
                    Section {
                        SecureField(String(localized: "Gateway token"), text: $credentialInputText)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Paste the OpenClaw Gateway bearer token. Whitespace and newlines are stripped automatically.")
                    }
                }
                .navigationTitle(credentialConfigured ? "Replace Credential" : "Enter Credential")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showCredentialInput = false
                            credentialInputText = ""
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let cleaned = credentialInputText.components(separatedBy: .whitespacesAndNewlines).joined()
                            guard !cleaned.isEmpty else { return }
                            _ = OpenClawBackendCredentialStore.save(cleaned)
                            credentialConfigured = OpenClawBackendCredentialStore.isConfigured
                            credentialInputText = ""
                            showCredentialInput = false
                        }
                        .disabled(credentialInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert(String(localized: "Remove Credential"), isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                OpenClawBackendCredentialStore.delete()
                credentialConfigured = OpenClawBackendCredentialStore.isConfigured
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The stored Gateway token will be removed from the Keychain.")
        }
        .alert(String(localized: "Cannot Save"), isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: loadSettings)
    }

    // MARK: - State

    private func loadSettings() {
        let config = OpenClawBackendConfigStore.load()
        baseURLText = config.baseURL.absoluteString
        agentIDText = config.agentID ?? ""
        credentialConfigured = OpenClawBackendCredentialStore.isConfigured
        active = AgentBackendConfigStore.loadActive()?.backendID == OpenClawBackend.backendID
    }

    /// Persists URL + agent ID. When the backend is active the active config is
    /// refreshed too so the agent ID change takes effect immediately.
    private func saveSettings() {
        guard let url = validatedBaseURL() else {
            errorMessage = String(localized: "Enter a valid backend URL with http:// or https://")
            showError = true
            return
        }
        let agentID = trimmedAgentID
        OpenClawBackendConfigStore.setBaseURL(url)
        OpenClawBackendConfigStore.setAgentID(agentID)
        if active {
            AgentBackendConfigStore.setActive(AgentBackendConfig(backendID: OpenClawBackend.backendID, agentID: agentID))
        }
    }

    /// Explicit activate/deactivate. Activation persists transport settings and
    /// writes the synthetic backend config through `AgentBackendConfigStore`.
    private func handleActiveChange(_ isOn: Bool) {
        if isOn {
            guard let url = validatedBaseURL() else {
                errorMessage = String(localized: "Enter a valid backend URL with http:// or https:// before activating.")
                showError = true
                active = false
                return
            }
            let agentID = trimmedAgentID
            OpenClawBackendConfigStore.setBaseURL(url)
            OpenClawBackendConfigStore.setAgentID(agentID)
            AgentBackendConfigStore.setActive(AgentBackendConfig(backendID: OpenClawBackend.backendID, agentID: agentID))
        } else {
            AgentBackendConfigStore.setActive(nil)
        }
    }

    private var trimmedAgentID: String? {
        let trimmed = agentIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func validatedBaseURL() -> URL? {
        let trimmed = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }
}
