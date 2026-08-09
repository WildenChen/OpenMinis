import Foundation

/// Stable identity for a configured external agent backend. Transport-specific
/// settings and credentials remain owned by the corresponding adapter.
struct AgentBackendConfig: Codable, Hashable, Sendable {
    /// Registry key for the adapter implementation (for example, `openclaw` or
    /// `hermes`). This is deliberately not a `ProviderType`: an external agent
    /// backend is an agent runtime, not another raw LLM wire format.
    let backendID: String
    /// The user-visible target inside the backend, such as an OpenClaw agent or
    /// a Hermes profile. Nil delegates target selection to the adapter.
    let agentID: String?

    init(backendID: String, agentID: String? = nil) {
        self.backendID = backendID
        self.agentID = agentID
    }
}

/// Canonical identity passed to every external backend turn. The OpenMinis chat
/// ID remains the source of truth; adapters may derive backend-native IDs from
/// `externalSessionKey`, but must never require a user-managed mapping per chat.
struct AgentBackendSession: Hashable, Sendable {
    let openMinisSessionID: String

    init(openMinisSessionID: String) {
        self.openMinisSessionID = openMinisSessionID
    }

    var externalSessionKey: String { "soulnest:\(openMinisSessionID)" }
}
