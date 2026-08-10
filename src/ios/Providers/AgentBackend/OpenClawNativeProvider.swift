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
        let request = AgentBackendRequest(
            session: AgentBackendSession(openMinisSessionID: sessionID),
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens,
            thinkingLevel: thinkingLevel
        )
        return Self.reliableOpenClawStream(backend: backend, request: request)
    }

    /// Small retry layer scoped only to OpenClaw. The generic OpenMinis retry
    /// helper returns as soon as it obtains an AsyncThrowingStream, so a network
    /// failure that happens while consuming that stream cannot be retried there.
    ///
    /// We retry only when a transient failure occurs BEFORE any stream event has
    /// been emitted. Once text/tool output has started, replaying the request
    /// could duplicate a turn already accepted by the persistent OpenClaw
    /// session, so the error is surfaced instead of guessing. Every retry uses
    /// the same AgentBackendRequest and therefore the exact same
    /// `soulnest:<OpenMinis chat id>` session identity.
    ///
    /// The same event stream also drives the Avatar presentation layer. This is
    /// intentionally one-way: Avatar state/subtitles observe agent lifecycle but
    /// never influence session routing, memory or tool ownership.
    static func reliableOpenClawStream(
        backend: OpenClawBackend,
        request: AgentBackendRequest
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let retryDelays: [UInt64] = [1, 3, 5]

        return AsyncThrowingStream { continuation in
            let task = Task {
                var attempt = 0
                var subtitleBuffer = ""
                var avatarIsTalking = false
                var lastSubtitlePublish = Date.distantPast
                await MainActor.run { SoulNestAvatarPresentation.thinking() }

                while !Task.isCancelled {
                    var emittedAnyEvent = false
                    do {
                        let upstream = try await backend.stream(request: request)
                        for try await event in upstream {
                            try Task.checkCancellation()
                            emittedAnyEvent = true

                            switch event {
                            case .textDelta(let delta):
                                subtitleBuffer += delta
                                if !avatarIsTalking {
                                    avatarIsTalking = true
                                    await MainActor.run { SoulNestAvatarPresentation.talking() }
                                }
                                let now = Date()
                                if now.timeIntervalSince(lastSubtitlePublish) >= 0.12 {
                                    lastSubtitlePublish = now
                                    let snapshot = subtitleBuffer
                                    await MainActor.run {
                                        SoulNestAvatarPresentation.talking(subtitle: snapshot)
                                    }
                                }

                            case .toolCallComplete:
                                // Device tool execution happens between this
                                // iteration and the follow-up request. Visually
                                // that is a processing/thinking phase, not speech.
                                avatarIsTalking = false
                                await MainActor.run { SoulNestAvatarPresentation.thinking() }

                            case .done(let reason):
                                switch reason {
                                case .toolUse:
                                    avatarIsTalking = false
                                    await MainActor.run { SoulNestAvatarPresentation.thinking() }
                                default:
                                    let finalSubtitle = subtitleBuffer
                                    await MainActor.run {
                                        if finalSubtitle.isEmpty {
                                            SoulNestAvatarPresentation.idle()
                                        } else {
                                            // `say` keeps the talking clip +
                                            // subtitle visible for a short
                                            // presentation window, matching the
                                            // existing Avatar shell fallback when
                                            // exact TTS completion metadata is not
                                            // available.
                                            SoulNestAvatarPresentation.say(finalSubtitle)
                                        }
                                    }
                                }

                            default:
                                break
                            }
                            continuation.yield(event)
                        }

                        // Some compatible gateways close the stream without an
                        // explicit final `done`. Do not leave the Avatar stuck in
                        // thinking/talking in that case.
                        let finalSubtitle = subtitleBuffer
                        await MainActor.run {
                            if finalSubtitle.isEmpty {
                                SoulNestAvatarPresentation.idle()
                            } else {
                                SoulNestAvatarPresentation.say(finalSubtitle)
                            }
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        await MainActor.run { SoulNestAvatarPresentation.idle(clearSubtitle: false) }
                        continuation.finish(throwing: CancellationError())
                        return
                    } catch {
                        let mapped = Self.mapOpenClawError(error)
                        if !emittedAnyEvent,
                           Self.isRetryableOpenClawError(mapped),
                           attempt < retryDelays.count {
                            let delay = retryDelays[attempt]
                            attempt += 1
                            await MainActor.run { SoulNestAvatarPresentation.thinking() }
                            do {
                                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                                continue
                            } catch {
                                await MainActor.run { SoulNestAvatarPresentation.idle(clearSubtitle: false) }
                                continuation.finish(throwing: CancellationError())
                                return
                            }
                        }
                        await MainActor.run { SoulNestAvatarPresentation.idle(clearSubtitle: false) }
                        continuation.finish(throwing: mapped)
                        return
                    }
                }
                await MainActor.run { SoulNestAvatarPresentation.idle(clearSubtitle: false) }
                continuation.finish(throwing: CancellationError())
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Normalize OpenClaw transport failures into the same error taxonomy the
    /// existing chat UI already understands. Keep response bodies short and do
    /// not include credentials or request payloads.
    private static func mapOpenClawError(_ error: Error) -> Error {
        if let llm = error as? LLMError { return llm }
        if let url = error as? URLError {
            if url.code == .cancelled { return LLMError.cancelled }
            return LLMError.networkError(underlying: url)
        }
        if let gateway = error as? OpenClawBackendError {
            switch gateway {
            case .http(let status, let body):
                switch status {
                case 401, 403:
                    return LLMError.invalidAPIKey(detail: "OpenClaw Gateway authentication failed (HTTP \(status)).")
                case 429:
                    return LLMError.rateLimited
                case 408, 425, 500...599:
                    return LLMError.transientError(message: "OpenClaw Gateway HTTP \(status)")
                default:
                    let compact = body
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let detail = compact.isEmpty ? "" : ": \(String(compact.prefix(240)))"
                    return LLMError.providerError(message: "OpenClaw Gateway HTTP \(status)\(detail)")
                }
            }
        }
        return LLMError.unknown(underlying: error)
    }

    private static func isRetryableOpenClawError(_ error: Error) -> Bool {
        (error as? LLMError)?.isRetryable == true
    }
}
