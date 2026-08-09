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
/// No settings UI yet — the value is written programmatically (SoulNest
/// onboarding / future settings screen). Reads are only hit from MainActor
/// chat-loop paths, but UserDefaults is thread-safe so the type is not actor
/// isolated.
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

    /// True when an external agent backend is currently the active brain.
    static var isActive: Bool { loadActive() != nil }
}

/// Resolves the synthetic model entry / backend provider the chat loop uses
/// when an external agent backend is active. Keeping both behind one helper
/// means the factory hooks (`resolveCurrentEntry`, `makeAgentProvider(for:)`)
/// only need a single registration point.
@MainActor
enum AgentBackendActiveState {
    /// providerInstanceId carried by the synthetic backend entry. Deliberately
    /// not a real ProviderInstance — the entry exists only to move the
    /// backend's model through the existing agent loop.
    static let syntheticProviderInstanceId = "__external_agent_backend__"

    /// Returns (backend provider, synthetic entry) for the active backend, or
    /// nil when none is configured / the adapter is not registered.
    static func resolved() -> (provider: AgentBackendProvider, entry: ModelEntry)? {
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
