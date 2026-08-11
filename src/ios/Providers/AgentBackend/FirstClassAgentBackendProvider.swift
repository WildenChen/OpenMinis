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

    /// OpenClaw's Gateway owner token is device-local by design. Its normal
    /// ProviderInstance keychain item contains only this non-secret marker so
    /// provider metadata may sync without ever syncing the owner credential.
    static func credential(for instance: ProviderInstance) -> String? {
        if instance.providerType == .openClaw {
            return OpenClawBackendCredentialStore.load()
        }
        return ProviderKeychainHelper.loadAPIKey(instanceId: instance.id)
    }

    @discardableResult
    static func saveCredential(_ credential: String, for instance: ProviderInstance) -> Bool {
        if instance.providerType == .openClaw {
            guard OpenClawBackendCredentialStore.save(credential) else { return false }
            ProviderKeychainHelper.saveAPIKey(legacyOpenClawCredentialMarker, instanceId: instance.id)
            return true
        }
        ProviderKeychainHelper.saveAPIKey(credential, instanceId: instance.id)
        return true
    }

    static func deleteCredential(for instance: ProviderInstance) {
        if instance.providerType == .openClaw {
            OpenClawBackendCredentialStore.delete()
        }
        ProviderKeychainHelper.deleteAPIKey(instanceId: instance.id)
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
              let token = FirstClassAgentBackendProvider.credential(for: instance), !token.isEmpty else {
            throw OpenClawFirstClassProviderError.missingCredential
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
        return OpenClawStreamReliability.stream(backend: backend, request: request)
    }
}

/// First-class Hermes provider.  It deliberately keeps Hermes request/session
/// semantics in `HermesBackend` rather than adding behavior to OpenAIProvider.
struct HermesFirstClassProvider: SessionAwareAgentProvider {
    let instance: ProviderInstance
    let model: LLMModel

    var name: String { "Hermes" }
    var defaultMaxTokens: Int { HermesBackend.defaultModel.maxOutputTokens ?? 16_384 }

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
              let credential = FirstClassAgentBackendProvider.credential(for: instance), !credential.isEmpty else {
            throw HermesFirstClassProviderError.missingCredential
        }
        let backend = HermesBackend(
            endpoint: endpoint,
            profileID: FirstClassAgentBackendProvider.targetID(for: instance),
            credential: credential,
            model: model
        )
        let request = AgentBackendRequest(
            session: AgentBackendSession(openMinisSessionID: sessionID), messages: messages,
            systemPrompt: systemPrompt, tools: tools, maxTokens: maxTokens, thinkingLevel: thinkingLevel
        )
        return HermesStreamReliability.stream(backend: backend, request: request)
    }
}

enum OpenClawFirstClassProviderError: LocalizedError {
    case missingCredential

    var errorDescription: String? {
        String(localized: "OpenClaw Gateway credential is not configured on this device. Open Providers → OpenClaw and enter the Gateway credential.")
    }
}

enum HermesFirstClassProviderError: LocalizedError {
    case missingCredential

    var errorDescription: String? {
        String(localized: "Hermes credential is not configured. Open Providers → Hermes and enter the endpoint credential.")
    }
}

/// Hermes retries only failures that occur before any event is delivered. The
/// original request (and therefore X-Hermes-Session-Id) is reused verbatim;
/// reconnecting can never manufacture a second Hermes conversation.
enum HermesStreamReliability {
    static func stream(
        backend: HermesBackend,
        request: AgentBackendRequest
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let retryDelays: [UInt64] = [1, 3, 5]
        return AsyncThrowingStream { continuation in
            let task = Task {
                var attempt = 0
                while !Task.isCancelled {
                    var emittedAnyEvent = false
                    do {
                        let upstream = try await backend.stream(request: request)
                        for try await event in upstream {
                            try Task.checkCancellation()
                            emittedAnyEvent = true
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                        return
                    } catch {
                        let mapped = map(error)
                        if !emittedAnyEvent, isRetryable(mapped), attempt < retryDelays.count {
                            let delay = retryDelays[attempt]
                            attempt += 1
                            do {
                                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                                continue
                            } catch {
                                continuation.finish(throwing: CancellationError())
                                return
                            }
                        }
                        continuation.finish(throwing: mapped)
                        return
                    }
                }
                continuation.finish(throwing: CancellationError())
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func map(_ error: Error) -> Error {
        if let llm = error as? LLMError { return llm }
        if let url = error as? URLError {
            return url.code == .cancelled ? LLMError.cancelled : LLMError.networkError(underlying: url)
        }
        if let hermes = error as? HermesBackendError {
            switch hermes {
            case .http(let status, let body):
                switch status {
                case 401, 403:
                    return LLMError.invalidAPIKey(detail: "Hermes authentication failed (HTTP \(status)).")
                case 429:
                    return LLMError.rateLimited
                case 408, 425, 500...599:
                    return LLMError.transientError(message: "Hermes HTTP \(status)")
                default:
                    let compact = body.replacingOccurrences(of: "\n", with: " ")
                    return LLMError.providerError(message: "Hermes HTTP \(status)\(compact.isEmpty ? "" : ": \(String(compact.prefix(240)))")")
                }
            }
        }
        return LLMError.unknown(underlying: error)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        (error as? LLMError)?.isRetryable == true
    }
}
