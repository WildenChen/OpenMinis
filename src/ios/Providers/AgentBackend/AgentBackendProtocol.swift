import Foundation

/// The complete provider-neutral input for an external agent backend turn.
/// Keeping this shape here lets OpenClaw and Hermes share the OpenMinis-facing
/// contract without placing either transport in an existing provider.
struct AgentBackendRequest: @unchecked Sendable {
    let session: AgentBackendSession
    let messages: [AgentMessage]
    let systemPrompt: String?
    let tools: [AgentToolDefinition]
    let maxTokens: Int
    let thinkingLevel: ThinkingLevel
}

/// Shared adapter contract for external agent runtimes. Implementations own
/// authentication, transport and backend-native session state; OpenMinis owns
/// the canonical chat/session identity and device-tool execution.
protocol ExternalAgentBackend {
    var name: String { get }
    var model: LLMModel { get }
    var defaultMaxTokens: Int { get }

    func stream(
        request: AgentBackendRequest
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error>
}

/// A narrow extension point for providers whose request needs an OpenMinis
/// session ID. Existing AgentProvider implementations keep their exact API.
protocol SessionAwareAgentProvider: AgentProvider {
    func streamAgentMessageClamped(
        sessionID: String,
        messages: [AgentMessage],
        systemPrompt: String?,
        tools: [AgentToolDefinition],
        maxTokens: Int,
        thinkingLevel: ThinkingLevel
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error>
}

extension SessionAwareAgentProvider {
    func streamAgentMessage(
        sessionID: String,
        messages: [AgentMessage],
        systemPrompt: String?,
        tools: [AgentToolDefinition],
        maxTokens: Int,
        thinkingLevel: ThinkingLevel
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let clamped = min(thinkingLevel, model.catalogMaxThinkingLevel)
        return try await streamAgentMessageClamped(
            sessionID: sessionID,
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens,
            thinkingLevel: clamped
        )
    }
}
