import Foundation

enum AgentBackendError: LocalizedError {
    case missingSessionID

    var errorDescription: String? {
        switch self {
        case .missingSessionID:
            return String(localized: "External agent backends require an OpenMinis chat session.")
        }
    }
}

/// Bridges an ExternalAgentBackend into the existing agent loop while keeping
/// the session-aware call separate from the global AgentProvider protocol.
struct AgentBackendProvider: SessionAwareAgentProvider {
    let backend: any ExternalAgentBackend

    var name: String { backend.name }
    var model: LLMModel { backend.model }
    var defaultMaxTokens: Int { backend.defaultMaxTokens }

    /// Deliberately unavailable for external backends: callers must provide the
    /// current chat ID through SessionAwareAgentProvider.
    func streamAgentMessageClamped(
        messages: [AgentMessage],
        systemPrompt: String?,
        tools: [AgentToolDefinition],
        maxTokens: Int,
        thinkingLevel: ThinkingLevel
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        throw AgentBackendError.missingSessionID
    }

    func streamAgentMessageClamped(
        sessionID: String,
        messages: [AgentMessage],
        systemPrompt: String?,
        tools: [AgentToolDefinition],
        maxTokens: Int,
        thinkingLevel: ThinkingLevel
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        try await backend.stream(request: AgentBackendRequest(
            session: AgentBackendSession(openMinisSessionID: sessionID),
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens,
            thinkingLevel: thinkingLevel
        ))
    }
}
