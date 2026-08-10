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
    /// Gateway bearer token. Nil → no `Authorization` header. Persisted only in
    /// the dedicated Keychain item (`OpenClawBackendCredentialStore`), never in
    /// UserDefaults or logs.
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

/// Reads OpenClaw transport settings. Base URL and agent ID are ordinary app
/// configuration in UserDefaults; the Gateway bearer token is an operator
/// credential and is read from the dedicated Keychain item
/// (`OpenClawBackendCredentialStore`), never from UserDefaults.
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
            gatewayToken: OpenClawBackendCredentialStore.load()
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

// MARK: - Native provider bridge

/// Compatibility marker that lets OpenClaw participate in OpenMinis' existing
/// ProviderInstance / ModelEntry UI without pretending the OpenClaw agent is an
/// OpenAI model at runtime.
///
/// Internally the persisted instance uses the existing `.openAI` protocol slot
/// so we do not expand ProviderType and every exhaustive provider switch just to
/// add an agent runtime. The marker is durable provider metadata; the actual
/// Gateway owner credential remains in the dedicated device-local Keychain item.
enum OpenClawNativeProvider {
    static let providerMarker = "SoulNest-OpenClaw"

    /// ProviderConfigStore's normal readiness / routing checks expect a provider
    /// credential. Store only this NON-SECRET marker in the ordinary provider
    /// Keychain; the real OpenClaw owner/operator token never leaves
    /// OpenClawBackendCredentialStore (ThisDeviceOnly, non-synchronizable).
    static let credentialMarker = "openclaw-managed-credential"

    /// Prevent generic OpenAI-only helper calls (for example title generation)
    /// from accidentally reaching the real Gateway. The main agent loop detects
    /// the provider marker and routes through OpenClawBackend before this URL is
    /// used. Transport URL remains adapter-owned in OpenClawBackendConfigStore.
    static let inertProviderBaseURL = "http://127.0.0.1:9"

    static func isInstance(_ instance: ProviderInstance) -> Bool {
        instance.providerType == .openAI && instance.effectiveCustomUserAgent == providerMarker
    }

    static func isProvider(_ provider: OpenAIProvider) -> Bool {
        provider.extraHeaders["User-Agent"] == providerMarker
    }
}

/// OpenAI-backed ProviderInstances normally use OpenAIAgentProvider. Native
/// OpenClaw instances intentionally reuse that existing factory path, then this
/// session-aware extension swaps only the runtime transport to OpenClawBackend.
/// Normal OpenAI providers simply delegate to their existing implementation.
extension OpenAIAgentProvider: SessionAwareAgentProvider {
    func streamAgentMessageClamped(
        sessionID: String,
        messages: [AgentMessage],
        systemPrompt: String?,
        tools: [AgentToolDefinition],
        maxTokens: Int,
        thinkingLevel: ThinkingLevel
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        guard OpenClawNativeProvider.isProvider(provider) else {
            return try await streamAgentMessageClamped(
                messages: messages,
                systemPrompt: systemPrompt,
                tools: tools,
                maxTokens: maxTokens,
                thinkingLevel: thinkingLevel
            )
        }

        let stored = OpenClawBackendConfigStore.load()
        let selectedAgentID = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = OpenClawBackendConfig(
            baseURL: stored.baseURL,
            agentID: selectedAgentID.isEmpty ? stored.agentID : selectedAgentID,
            gatewayToken: stored.gatewayToken,
            model: OpenClawBackend.defaultModel
        )
        let backend = OpenClawBackend(config: config)
        return try await backend.stream(request: AgentBackendRequest(
            session: AgentBackendSession(openMinisSessionID: sessionID),
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens,
            thinkingLevel: thinkingLevel
        ))
    }
}
