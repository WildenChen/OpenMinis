import Foundation

/// Provider-layer placeholder for Hermes. Its configuration and session-aware
/// contract are first-class now; a deployment-specific Hermes transport can be
/// registered later without changing ProviderType, picker, or chat routing.
struct HermesBackend: ExternalAgentBackend {
    static let defaultModel = LLMModel(
        id: "hermes", displayName: "Hermes", provider: "Hermes",
        contextWindow: 1_000_000, maxOutputTokens: 16_384, supportsReasoning: false
    )

    let endpoint: URL
    let profileID: String?
    let credential: String?
    let model: LLMModel

    var name: String { "Hermes" }
    var defaultMaxTokens: Int { model.maxOutputTokens ?? 16_384 }

    init(endpoint: URL, profileID: String?, credential: String?, model: LLMModel) {
        self.endpoint = endpoint
        self.profileID = profileID
        self.credential = credential
        self.model = model
    }

    func stream(request: AgentBackendRequest) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        throw HermesBackendError.transportUnavailable
    }
}

enum HermesBackendError: LocalizedError {
    case transportUnavailable

    var errorDescription: String? {
        String(localized: "Hermes is configured, but this app build does not yet include a Hermes runtime transport.")
    }
}
