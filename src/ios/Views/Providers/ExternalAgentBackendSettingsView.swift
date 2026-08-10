import SwiftUI

/// OpenClaw configuration presented from the normal Providers screen.
///
/// OpenClaw is persisted as a real ProviderInstance and each OpenClaw agent is
/// a normal ModelEntry, so chat readiness, the session model picker and session
/// bindings all use OpenMinis' existing provider/model flow. Only the transport
/// remains adapter-specific.
///
/// Security boundary:
///   - Gateway URL → OpenClawBackendConfigStore (ordinary local config)
///   - Gateway owner token → OpenClawBackendCredentialStore (ThisDeviceOnly Keychain)
///   - ProviderConfigStore receives only a non-secret credential marker so its
///     existing readiness/routing logic can treat the provider as configured.
struct ExternalAgentBackendSettingsView: View {
    @ObservedObject private var store = ProviderConfigStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var baseURLText = ""
    @State private var agentIDText = "yujie"
    @State private var agentDisplayNameText = "語婕"
    @State private var credentialConfigured = false

    @State private var showCredentialInput = false
    @State private var credentialInputText = ""
    @State private var showRemoveConfirm = false
    @State private var showDeleteProviderConfirm = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var nativeInstance: ProviderInstance? {
        store.instances.first(where: OpenClawNativeProvider.isInstance)
    }

    private var configuredAgents: [ModelEntry] {
        guard let instance = nativeInstance else { return [] }
        return store.visibleEntries(for: instance.id)
    }

    var body: some View {
        Form {
            if let instance = nativeInstance {
                Section("Provider") {
                    HStack {
                        Text("OpenClaw")
                        Spacer()
                        Text("Provider")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Enabled", isOn: Binding(
                        get: { instance.isEnabled },
                        set: { setProviderEnabled($0) }
                    ))
                }
            }

            Section {
                TextField(String(localized: "Gateway URL"), text: $baseURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Gateway URL")
            } footer: {
                Text("OpenClaw Gateway base URL, e.g. http://127.0.0.1:18789")
            }

            Section {
                HStack {
                    Image(systemName: credentialConfigured ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(credentialConfigured ? Color.green : Color.secondary)
                    Text(credentialConfigured
                         ? String(localized: "Credential configured on this device")
                         : String(localized: "No credential configured on this device"))
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
                Text("The owner/operator bearer token stays in this iPhone's Keychain and is never synced or redisplayed.")
            }

            Section {
                TextField(String(localized: "Agent ID"), text: $agentIDText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(String(localized: "Display Name"), text: $agentDisplayNameText)
                    .textContentType(.name)
            } header: {
                Text(nativeInstance == nil ? "Initial Agent" : "Add or Update Agent")
            } footer: {
                Text("Each OpenClaw agent is stored as a normal model. For example, agent ID yujie can be shown as 語婕 in the model picker.")
            }

            if !configuredAgents.isEmpty {
                Section("Agents / Models") {
                    ForEach(configuredAgents) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.model.displayName)
                                Text(entry.baseModel.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                store.removeEntry(entry.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section {
                Button {
                    saveConfiguration()
                } label: {
                    HStack {
                        Spacer()
                        Text(nativeInstance == nil ? "Add OpenClaw Provider" : "Save & Add/Update Agent")
                            .font(.body.weight(.semibold))
                        Spacer()
                    }
                }
                .disabled(agentIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if nativeInstance != nil {
                Section {
                    Button("Delete OpenClaw Provider", role: .destructive) {
                        showDeleteProviderConfirm = true
                    }
                }
            }
        }
        .navigationTitle("OpenClaw")
        .navigationBarTitleDisplayMode(.inline)
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
                            saveCredential()
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
                // The ProviderConfigStore carries only a non-secret readiness
                // marker, so disable the provider when the real credential is
                // removed to avoid selecting a backend that cannot authenticate.
                setProviderEnabled(false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The stored Gateway token will be removed from this device.")
        }
        .alert(String(localized: "Delete OpenClaw Provider"), isPresented: $showDeleteProviderConfirm) {
            Button("Delete", role: .destructive) {
                deleteProvider()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the OpenClaw provider and its agent/model entries from OpenMinis, and removes the Gateway token from this device.")
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
        credentialConfigured = OpenClawBackendCredentialStore.isConfigured

        if let first = configuredAgents.first {
            agentIDText = first.baseModel.id
            agentDisplayNameText = first.model.displayName
        } else {
            agentIDText = config.agentID ?? "yujie"
            agentDisplayNameText = agentIDText == "yujie" ? "語婕" : agentIDText
        }
    }

    private func saveCredential() {
        let cleaned = credentialInputText.components(separatedBy: .whitespacesAndNewlines).joined()
        guard !cleaned.isEmpty else { return }
        guard OpenClawBackendCredentialStore.save(cleaned) else {
            errorMessage = String(localized: "Failed to save the Gateway credential to the iOS Keychain. Please try again.")
            showError = true
            return
        }
        credentialConfigured = true
        credentialInputText = ""
        showCredentialInput = false
    }

    private func saveConfiguration() {
        guard let url = validatedBaseURL() else {
            showSaveError(String(localized: "Enter a valid Gateway URL with http:// or https://"))
            return
        }
        guard OpenClawBackendCredentialStore.isConfigured else {
            showSaveError(String(localized: "Enter the Gateway credential before adding or enabling OpenClaw."))
            return
        }

        let agentID = agentIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agentID.isEmpty else {
            showSaveError(String(localized: "Enter an OpenClaw agent ID."))
            return
        }
        let requestedName = agentDisplayNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = requestedName.isEmpty ? (agentID == "yujie" ? "語婕" : agentID) : requestedName

        // Transport remains adapter-owned. The selected ModelEntry supplies the
        // agent ID at request time; keeping this value too preserves compatibility
        // with the previously shipped OpenClaw config and makes migration benign.
        OpenClawBackendConfigStore.setBaseURL(url)
        OpenClawBackendConfigStore.setAgentID(agentID)

        if let instance = nativeInstance {
            ensureAgent(agentID: agentID, displayName: displayName, instance: instance)
            if !instance.isEnabled { setProviderEnabled(true) }
        } else {
            guard createNativeProvider(agentID: agentID, displayName: displayName) else { return }
        }

        // A real ProviderInstance is now the source of chat selection. Disable
        // the legacy synthetic-backend shortcut so it can no longer override the
        // session's normal provider/model binding.
        AgentBackendConfigStore.setActive(nil)
    }

    private func createNativeProvider(agentID: String, displayName: String) -> Bool {
        let markerB64 = Data(OpenClawNativeProvider.credentialMarker.utf8).base64EncodedString()
        let payload: [String: Any] = [
            "providerType": ProviderType.openAI.rawValue,
            "label": "OpenClaw",
            "credentialType": ProviderCredential.apiKey.rawValue,
            // Generic OpenAI helper calls must not hit the real Gateway. The
            // session-aware agent path uses OpenClawBackendConfigStore instead.
            "customBaseURL": OpenClawNativeProvider.inertProviderBaseURL,
            "appendV1Suffix": false,
            "customUserAgent": OpenClawNativeProvider.providerMarker,
            "apiKey": markerB64,
            "models": [[
                "modelId": agentID,
                "displayName": displayName,
                "isCustom": true,
                "isHidden": false,
                "contextWindow": 1_000_000,
                "maxOutputTokens": 16_384,
                "supportsReasoning": false,
            ]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8),
              store.importInstanceJSON(json) != nil else {
            showSaveError(String(localized: "Failed to add the OpenClaw provider."))
            return false
        }
        return true
    }

    private func ensureAgent(agentID: String, displayName: String, instance: ProviderInstance) {
        if var existing = store.entries(for: instance.id).first(where: { $0.baseModel.id == agentID }) {
            if existing.model.displayName != displayName {
                existing.overrides.displayName = displayName
                store.updateEntry(existing)
            }
            return
        }

        let model = LLMModel(
            id: agentID,
            displayName: displayName,
            provider: "OpenClaw",
            modalityOverride: [.textInput, .textOutput],
            contextWindow: 1_000_000,
            maxOutputTokens: 16_384,
            supportsReasoning: false
        )
        _ = store.addEntry(ModelEntry(
            providerInstanceId: instance.id,
            model: model,
            isCustom: true
        ))
    }

    private func setProviderEnabled(_ enabled: Bool) {
        guard var instance = nativeInstance, instance.isEnabled != enabled else { return }
        instance.isEnabled = enabled
        store.updateInstance(instance)
    }

    private func deleteProvider() {
        if let instance = nativeInstance {
            store.removeInstance(instance.id)
        }
        OpenClawBackendCredentialStore.delete()
        OpenClawBackendConfigStore.setBaseURL(nil)
        OpenClawBackendConfigStore.setAgentID(nil)
        AgentBackendConfigStore.setActive(nil)
        dismiss()
    }

    private func showSaveError(_ message: String) {
        errorMessage = message
        showError = true
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
