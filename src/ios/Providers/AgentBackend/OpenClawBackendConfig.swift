import Foundation

/// Transport settings for the OpenClaw gateway adapter. Kept separate from the
/// registry-level `AgentBackendConfig` so the adapter owns its wire details
/// and credentials.
struct OpenClawBackendConfig: Sendable {
    /// OpenClaw gateway default base URL (OpenAI-compatible `/v1/...`).
    static let defaultBaseURL = URL(string: "http://127.0.0.1:18789")!

    let baseURL: URL
    /// Target OpenClaw agent (e.g. `yujie`). Nil delegates to the gateway's
    /// default agent.
    let agentID: String?
    /// Gateway bearer token. Nil → no `Authorization` header. Not persisted
    /// anywhere (see `OpenClawBackendConfigStore`); callers must inject it
    /// programmatically, and it is never written to logs.
    let gatewayToken: String?
    let model: LLMModel

    init(
        baseURL: URL = OpenClawBackendConfig.defaultBaseURL,
        agentID: String? = nil,
        gatewayToken: String? = nil,
        model: LLMModel = OpenClawBackend.defaultModel
    ) {
        self.baseURL = baseURL
        self.agentID = agentID
        self.gatewayToken = gatewayToken
        self.model = model
    }
}

/// Reads OpenClaw transport settings from UserDefaults. No settings UI yet —
/// these keys are the programmatic setup surface (SoulNest onboarding / debug).
///
/// The gateway bearer token grants full owner/operator access, so it is
/// deliberately NOT persisted here (or anywhere else yet); it must be injected
/// programmatically via `OpenClawBackendConfig(gatewayToken:)` until Keychain-
/// backed credential storage lands.
///
/// Keys:
///   - `soulnest.openclaw.baseURL`      default `http://127.0.0.1:18789`
///   - `soulnest.openclaw.agentID`      nil → gateway default agent
enum OpenClawBackendConfigStore {
    private static let baseURLKey = "soulnest.openclaw.baseURL"
    private static let agentIDKey = "soulnest.openclaw.agentID"

    static func load() -> OpenClawBackendConfig {
        let ud = UserDefaults.standard
        let baseURL = ud.string(forKey: baseURLKey).flatMap(URL.init(string:)) ?? OpenClawBackendConfig.defaultBaseURL
        return OpenClawBackendConfig(
            baseURL: baseURL,
            agentID: ud.string(forKey: agentIDKey),
            gatewayToken: nil
        )
    }

    static func setBaseURL(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: baseURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: baseURLKey)
        }
    }

    static func setAgentID(_ id: String?) {
        if let id {
            UserDefaults.standard.set(id, forKey: agentIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: agentIDKey)
        }
    }
}
