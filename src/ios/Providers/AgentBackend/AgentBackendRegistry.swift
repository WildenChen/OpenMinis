import Foundation

/// Adapter registration belongs to the shared backend boundary. Issue-specific
/// adapters register their own factories here without modifying the chat loop
/// or any existing raw-LLM provider.
@MainActor
enum AgentBackendRegistry {
    typealias Factory = (AgentBackendConfig, LLMModel) throws -> any ExternalAgentBackend

    private static var factories: [String: Factory] = [:]

    static func register(backendID: String, factory: @escaping Factory) {
        factories[backendID] = factory
    }

    static func makeProvider(
        config: AgentBackendConfig,
        model: LLMModel
    ) throws -> AgentBackendProvider? {
        guard let factory = factories[config.backendID] else { return nil }
        return AgentBackendProvider(backend: try factory(config, model))
    }
}
