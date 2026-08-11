import Foundation

private let logger = AppLogger(category: "HermesBackend")

/// OpenAI-compatible adapter for a Hermes API Server.
///
/// Hermes owns the agent, its memory and host-side tools.  The phone supplies a
/// stable, authenticated session header, so every OpenMinis chat has exactly
/// one Hermes conversation without storing a second mapping on-device.
struct HermesBackend: ExternalAgentBackend {
    static let backendID = "hermes"
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
        var urlRequest = try Self.urlRequest(
            endpoint: endpoint,
            profileID: profileID,
            credential: credential,
            model: model,
            request: request
        )
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: Self.body(for: request, model: model), options: [.sortedKeys]
        )
        logger.info("Hermes stream session=\(request.session.externalSessionKey) profile=\(profileID ?? "default")")

        let (byteStream, response) = try await Self.session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            var errorBody = ""
            for try await line in byteStream.lines { errorBody += line }
            throw HermesBackendError.http(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                body: String(errorBody.prefix(1000))
            )
        }

        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in byteStream.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return OpenClawBackend.parseSSE(lines)
    }

    /// Pure request construction helpers are deliberately package-visible for
    /// focused adapter tests.  A configured endpoint may be either the server
    /// root or the exact chat-completions URL.
    static func chatURL(endpoint: URL, profileID: String?) -> URL {
        let normalizedPath = endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("v1/chat/completions") { return endpoint }
        var base = endpoint
        if let profileID, !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base.appendPathComponent("p")
            base.appendPathComponent(profileID)
        }
        base.appendPathComponent("v1")
        base.appendPathComponent("chat")
        base.appendPathComponent("completions")
        return base
    }

    static func body(for request: AgentBackendRequest, model: LLMModel) -> [String: Any] {
        var body: [String: Any] = [
            "model": model.id,
            "messages": OpenClawBackend.convertMessages(OpenClawBackend.currentTurnDelta(request.messages)),
            "stream": true,
        ]
        if request.maxTokens > 0 { body["max_tokens"] = request.maxTokens }
        return body
    }

    static func urlRequest(
        endpoint: URL, profileID: String?, credential: String?, model: LLMModel,
        request: AgentBackendRequest
    ) throws -> URLRequest {
        var result = URLRequest(url: chatURL(endpoint: endpoint, profileID: profileID))
        result.httpMethod = "POST"
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue(request.session.externalSessionKey, forHTTPHeaderField: "X-Hermes-Session-Id")
        // Scope Hermes long-term memory to the same stable mobile chat key.
        result.setValue(request.session.externalSessionKey, forHTTPHeaderField: "X-Hermes-Session-Key")
        if let credential, !credential.isEmpty {
            result.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }
        return result
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        let session = URLSession(configuration: config)
        LLMSessionRegistry.shared.register(session)
        return session
    }()
}

enum HermesBackendError: LocalizedError {
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            return "Hermes returned HTTP \(status): \(body)"
        }
    }
}
