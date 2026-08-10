import Foundation

/// Persistence for the single "active" external agent backend. When a backend
/// is active it becomes the only brain: the chat loop resolves to a synthetic
/// model entry and routes every turn through `AgentBackendProvider` instead of
/// a raw-LLM provider.
///
/// This store only holds the registry-level identity (`backendID` + `agentID`).
/// Transport settings and credentials stay inside each adapter
/// (`OpenClawBackendConfigStore`).
///
/// Kept for migration/backward compatibility. New OpenClaw configuration is a
/// normal ProviderInstance/ModelEntry and no longer writes this active state.
enum AgentBackendConfigStore {
    private static let defaultsKey = "soulnest.agentBackend.config"

    static func loadActive() -> AgentBackendConfig? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(AgentBackendConfig.self, from: data)
        else { return nil }
        return config
    }

    static func setActive(_ config: AgentBackendConfig?) {
        if let config, let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    /// True when a legacy external agent backend is currently the active brain.
    static var isActive: Bool { loadActive() != nil }
}

/// Resolves the legacy synthetic model entry / backend provider. A native
/// OpenClaw ProviderInstance always wins: once it exists, normal provider/model
/// selection is authoritative and any stale pre-migration Active toggle is
/// ignored even before the user revisits OpenClaw settings.
@MainActor
enum AgentBackendActiveState {
    /// providerInstanceId carried by the synthetic backend entry. Deliberately
    /// not a real ProviderInstance — retained only for migration compatibility.
    static let syntheticProviderInstanceId = "__external_agent_backend__"

    /// True when a native OpenClaw ProviderInstance already exists. Wired at
    /// launch by `OpenClawNativeProvider.install()` so this file stays free of
    /// app-only types and remains compilable by the unit-test target.
    static var nativeOpenClawExists: () -> Bool = { false }

    /// Returns (backend provider, synthetic entry) for the legacy active backend,
    /// or nil when a native OpenClaw provider exists / nothing is configured /
    /// the adapter is not registered.
    static func resolved() -> (provider: AgentBackendProvider, entry: ModelEntry)? {
        if nativeOpenClawExists() {
            return nil
        }
        guard let config = AgentBackendConfigStore.loadActive() else { return nil }
        let model: LLMModel
        switch config.backendID {
        case OpenClawBackend.backendID:
            model = OpenClawBackend.defaultModel
        default:
            return nil
        }
        guard let backend = try? AgentBackendRegistry.makeProvider(config: config, model: model) else {
            return nil
        }
        let entry = ModelEntry(providerInstanceId: syntheticProviderInstanceId, model: backend.model)
        return (backend, entry)
    }

    static func provider() -> AgentBackendProvider? { resolved()?.provider }
    static func modelEntry() -> ModelEntry? { resolved()?.entry }

    static func isBackendEntry(_ entry: ModelEntry) -> Bool {
        entry.providerInstanceId == syntheticProviderInstanceId
    }
}
