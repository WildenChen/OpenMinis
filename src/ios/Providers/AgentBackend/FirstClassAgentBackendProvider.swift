import Foundation

/// Non-secret, per-provider settings that do not belong in the generic
/// ProviderInstance schema. Endpoints live on ProviderInstance.customBaseURL;
/// credentials remain in the normal provider Keychain item.
enum AgentBackendProviderSettings {
    private static let targetIDsKey = "soulnest.agentBackend.providerTargetIDs"

    static func targetID(for instanceID: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: targetIDsKey) as? [String: String])?[instanceID]
    }

    static func setTargetID(_ targetID: String?, for instanceID: String) {
        var values = UserDefaults.standard.dictionary(forKey: targetIDsKey) as? [String: String] ?? [:]
        let cleaned = targetID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleaned, !cleaned.isEmpty {
            values[instanceID] = cleaned
        } else {
            values.removeValue(forKey: instanceID)
        }
        UserDefaults.standard.set(values, forKey: targetIDsKey)
    }

    static func remove(instanceID: String) {
        setTargetID(nil, for: instanceID)
    }
}

enum FirstClassAgentBackendProvider {
    /// Durable marker written by the pre-Issue-42 compatibility layer.
    static let legacyOpenClawMarker = "SoulNest-OpenClaw"
    static let legacyOpenClawCredentialMarker = "openclaw-managed-credential"
    static func isAgentBackend(_ type: ProviderType) -> Bool {
        type == .openClaw || type == .hermes
    }

    static func targetID(for instance: ProviderInstance) -> String? {
        AgentBackendProviderSettings.targetID(for: instance.id)
    }

    static func seedModel(for instance: ProviderInstance) -> LLMModel {
        let target = targetID(for: instance)
        let base = instance.providerType == .openClaw ? OpenClawBackend.defaultModel : HermesBackend.defaultModel
        guard let target, !target.isEmpty else { return base }
        return LLMModel(
            id: target,
            displayName: target,
            provider: base.provider,
            contextWindow: base.contextWindow,
            maxOutputTokens: base.maxOutputTokens,
            supportsReasoning: false
        )
    }
}

/// Formal ProviderType bridge for OpenClaw. It retains the existing adapter's
/// wire format, stable session key, tool routing, and pre-output retry policy.
struct OpenClawFirstClassProvider: SessionAwareAgentProvider {
    let instance: ProviderInstance
    let model: LLMModel

    var name: String { "OpenClaw" }
    var defaultMaxTokens: Int { OpenClawBackend.defaultModel.maxOutputTokens ?? 16_384 }

    func streamAgentMessageClamped(
        messages: [AgentMessage], systemPrompt: String?, tools: [AgentToolDefinition],
        maxTokens: Int, thinkingLevel: ThinkingLevel
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        throw AgentBackendError.missingSessionID
    }

    func streamAgentMessageClamped(
        sessionID: String, messages: [AgentMessage], systemPrompt: String?, tools: [AgentToolDefinition],
        maxTokens: Int, thinkingLevel: ThinkingLevel
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        guard let endpoint = instance.effectiveCustomBaseURL.flatMap(URL.init(string:)),
              let token = ProviderKeychainHelper.loadAPIKey(instanceId: instance.id), !token.isEmpty else {
            throw OpenClawNativeProviderError.missingCredential
        }
        let backend = OpenClawBackend(config: OpenClawBackendConfig(
            baseURL: endpoint,
            agentID: FirstClassAgentBackendProvider.targetID(for: instance) ?? model.id,
            gatewayToken: token
        ))
        let request = AgentBackendRequest(
            session: AgentBackendSession(openMinisSessionID: sessionID), messages: messages,
            systemPrompt: systemPrompt, tools: tools, maxTokens: maxTokens, thinkingLevel: thinkingLevel
        )
        return OpenAIAgentProvider.reliableOpenClawStream(backend: backend, request: request)
    }
}
