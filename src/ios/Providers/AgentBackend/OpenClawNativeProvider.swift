import Foundation

/// Compatibility marker that lets OpenClaw participate in OpenMinis' existing
/// ProviderInstance / ModelEntry UI without pretending the OpenClaw agent is an
/// OpenAI model at runtime.
///
/// Internally the persisted instance uses the existing `.openAI` protocol slot
/// so we do not expand ProviderType and every exhaustive provider switch just to
/// add an agent runtime. The marker is durable provider metadata; the actual
/// Gateway owner credential remains in the dedicated device-local Keychain item.
///
/// Kept out of the unit-test target on purpose: this file only exists in the app
/// bundle, where ProviderInstance / OpenAIProvider are available.
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

    /// Wires app-only provider knowledge into the backend abstraction. Called
    /// once at launch so `AgentBackendActiveState` (which stays testable) can
    /// consult the real ProviderConfigStore without depending on app-only types.
    @MainActor
    static func install() {
        AgentBackendActiveState.nativeOpenClawExists = {
            ProviderConfigStore.shared.instances.contains(where: isInstance)
        }
    }
}

enum OpenClawNativeProviderError: LocalizedError {
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return String(localized: "OpenClaw Gateway credential is not configured on this device. Open Providers → OpenClaw and enter the Gateway credential.")
        }
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
        guard let gatewayToken = stored.gatewayToken, !gatewayToken.isEmpty else {
            throw OpenClawNativeProviderError.missingCredential
        }
        let selectedAgentID = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = OpenClawBackendConfig(
            baseURL: stored.baseURL,
            agentID: selectedAgentID.isEmpty ? stored.agentID : selectedAgentID,
            gatewayToken: gatewayToken,
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
