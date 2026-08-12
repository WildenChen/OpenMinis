import Foundation

/// OpenClaw-specific streaming reliability is intentionally owned by the
/// first-class OpenClaw provider, rather than an OpenAI marker/provider path.
enum OpenClawStreamReliability {
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
    static func stream(
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
                                            // Text-only replies keep the final
                                            // subtitle briefly, then return to
                                            // idle. When reply TTS can play, its
                                            // actual playback lifecycle remains
                                            // authoritative for the idle transition.
                                            SoulNestAvatarPresentation.responseCompleted(
                                                finalSubtitle,
                                                hasTTSPlayback: VoiceOutputState.shared.canPlay
                                            )
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
                                SoulNestAvatarPresentation.responseCompleted(
                                    finalSubtitle,
                                    hasTTSPlayback: VoiceOutputState.shared.canPlay
                                )
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
