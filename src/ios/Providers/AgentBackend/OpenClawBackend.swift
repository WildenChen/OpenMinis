import Foundation

private let logger = AppLogger(category: "OpenClawBackend")

enum OpenClawBackendError: LocalizedError {
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            return "OpenClaw gateway returned HTTP \(status): \(body)"
        }
    }
}

/// OpenAI-compatible adapter for the OpenClaw gateway
/// (`POST {base}/v1/chat/completions`, Bearer auth, SSE stream).
///
/// Session continuity: the canonical OpenMinis chat id travels in the `user`
/// field as `soulnest:<openminis-session-id>`, which the gateway derives a
/// stable agent-session key from. Reopening the same OpenMinis chat therefore
/// resumes the same OpenClaw session; a new OpenMinis chat gets a fresh one.
/// No per-chat mapping is stored on the device.
///
/// Ownership: OpenMinis keeps device-tool execution and passes its tool set
/// through unchanged; OpenClaw decides which of those tools to call and runs
/// its own host-side tools. OpenClaw owns agent memory and context management.
struct OpenClawBackend: ExternalAgentBackend {

    static let backendID = "openclaw"

    /// The OpenClaw agent brain is fixed from the app's perspective — OpenMinis
    /// never picks the backend's underlying model. This `LLMModel` only feeds
    /// the loop's token budget and chat-header display. Context is treated as
    /// large because OpenClaw manages context itself.
    static let defaultModel = LLMModel(
        id: "openclaw",
        displayName: "OpenClaw",
        provider: "OpenClaw",
        contextWindow: 1_000_000,
        maxOutputTokens: 16_384,
        supportsReasoning: false
    )

    var name: String { "OpenClaw" }
    var model: LLMModel { config.model }
    var defaultMaxTokens: Int { OpenClawBackend.defaultModel.maxOutputTokens ?? 16_384 }

    let config: OpenClawBackendConfig

    /// Transport config comes from `OpenClawBackendConfigStore` unless a config
    /// is injected explicitly (tests). Callers construct this on the main
    /// thread via the registry factory.
    init(config: OpenClawBackendConfig = OpenClawBackendConfigStore.load()) {
        self.config = config
    }

    // MARK: - ExternalAgentBackend

    func stream(request: AgentBackendRequest) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let messages = Self.wireMessages(request.messages)

        var body: [String: Any] = [
            "model": model.id,
            "messages": messages,
            "stream": true,
            // Stable gateway session key derived from the OpenMinis chat id.
            "user": request.session.externalSessionKey,
        ]
        if !request.tools.isEmpty {
            body["tools"] = Self.convertTools(request.tools)
        }
        if request.maxTokens > 0 {
            body["max_tokens"] = request.maxTokens
        }
        logger.info("OpenClaw stream session=\(request.session.externalSessionKey) agent=\(config.agentID ?? "default") tools=\(request.tools.count)")

        let url = config.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = config.gatewayToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let agentID = config.agentID, !agentID.isEmpty {
            req.setValue(agentID, forHTTPHeaderField: "x-openclaw-agent-id")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (byteStream, response) = try await Self.session.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            var errBody = ""
            for try await line in byteStream.lines { errBody += line }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenClawBackendError.http(status: status, body: String(errBody.prefix(1000)))
        }

        let lineStream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in byteStream.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return Self.parseSSE(lineStream)
    }

    // MARK: - SSE Parsing

    /// Consumes OpenAI Chat Completions SSE lines and emits agent stream events.
    /// Shared by the adapter and the unit tests.
    static func parseSSE(_ lineStream: AsyncThrowingStream<String, Error>) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Streamed tool-call accumulation by `index`.
                var toolAccum: [Int: (id: String, name: String, json: String)] = [:]
                var sawAnyTool = false
                var emittedTextStart = false
                // Flushes every complete accumulated tool call in index order and
                // ends the turn. Shared by the `finish_reason: "tool_calls"`
                // branch and the `[DONE]` tail so a gateway that omits the final
                // finish chunk never silently drops an in-flight tool call.
                func flushToolCalls() {
                    for (_, acc) in toolAccum.sorted(by: { $0.key < $1.key }) {
                        guard !acc.id.isEmpty, !acc.name.isEmpty else { continue }
                        continuation.yield(.toolCallComplete(
                            id: sanitizeToolId(acc.id),
                            name: Self.decodedToolName(acc.name),
                            args: Self.parseArgs(acc.json),
                            metadata: nil
                        ))
                    }
                    continuation.yield(.done(stopReason: .toolUse))
                }
                do {
                    for try await line in lineStream {
                        guard let payload = Self.ssePayload(from: line) else { continue }
                        if payload == "[DONE]" {
                            if sawAnyTool {
                                flushToolCalls()
                            } else {
                                continuation.yield(.done(stopReason: .endTurn))
                            }
                            break
                        }
                        guard let dict = Self.jsonDict(payload) else { continue }

                        if let usage = dict["usage"] as? [String: Any] {
                            let input = usage["prompt_tokens"] as? Int ?? 0
                            let output = usage["completion_tokens"] as? Int ?? 0
                            continuation.yield(.usage(LLMUsage(
                                inputTokens: input,
                                outputTokens: output,
                                cacheCreationInputTokens: nil,
                                cacheReadInputTokens: nil
                            )))
                        }

                        guard let choices = dict["choices"] as? [[String: Any]],
                              let choice = choices.first else { continue }

                        // Some gateways omit `delta` on the final chunk and send only
                        // `finish_reason`. Process content/tool deltas first so a chunk
                        // carrying BOTH the last arguments delta and `finish_reason`
                        // (typical for tool calls) still emits its final deltas.
                        let delta = choice["delta"] as? [String: Any] ?? [:]

                        if let content = delta["content"] as? String, !content.isEmpty {
                            if !emittedTextStart {
                                continuation.yield(.contentBlockStart(.text))
                                emittedTextStart = true
                            }
                            continuation.yield(.textDelta(content))
                        }

                        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                            for tc in toolCalls {
                                guard let index = tc["index"] as? Int else { continue }
                                var acc = toolAccum[index] ?? ("", "", "")
                                if let id = tc["id"] as? String, !id.isEmpty { acc.id = id }
                                if let fn = tc["function"] as? [String: Any] {
                                    if let name = fn["name"] as? String, !name.isEmpty { acc.name = name }
                                    if let args = fn["arguments"] as? String, !args.isEmpty {
                                        acc.json += args
                                        sawAnyTool = true
                                        let streamName = acc.name.isEmpty ? "function" : Self.decodedToolName(acc.name)
                                        continuation.yield(.toolInputDelta(name: streamName, accumulated: acc.json))
                                    }
                                }
                                toolAccum[index] = acc
                            }
                        }

                        if let finish = choice["finish_reason"] as? String {
                            switch finish {
                            case "tool_calls":
                                sawAnyTool = true
                                flushToolCalls()
                            case "stop":
                                continuation.yield(.done(stopReason: .endTurn))
                            case "length":
                                continuation.yield(.done(stopReason: .maxTokens))
                            case "refusal":
                                continuation.yield(.done(stopReason: .refusal))
                            default:
                                continue
                            }
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Wire Format Conversion (OpenAI Chat Completions)

    /// Reversible namespace prefix for OpenMinis-provided (device-side) tools on
    /// the OpenClaw wire. OpenClaw v2026.6.34 can reject a client-tool name that
    /// collides with an OpenClaw-internal tool, so every OpenMinis tool is
    /// prefixed before it leaves the device and stripped again when OpenClaw
    /// calls it back. OpenClaw-native (host-side) tool names are left untouched.
    static let clientToolPrefix = "minis_"

    /// Encodes an OpenMinis tool name for the OpenClaw wire. Injective: two
    /// distinct client tools never map to the same wire name, including client
    /// tools whose names already carry the prefix.
    static func encodedToolName(_ name: String) -> String {
        clientToolPrefix + name
    }

    /// Decodes a tool name returned by OpenClaw. Names in the `minis_` namespace
    /// are stripped back to the OpenMinis tool name; anything else is an
    /// OpenClaw-native tool and passes through unchanged.
    static func decodedToolName(_ name: String) -> String {
        guard name.hasPrefix(clientToolPrefix) else { return name }
        return String(name.dropFirst(clientToolPrefix.count))
    }

    /// The only system message on the OpenClaw wire. The OpenMinis base prompt,
    /// Skills/MCP and local memory are NOT forwarded — OpenClaw/Yujie owns
    /// identity, memory and context. This fixed adapter policy only reinforces
    /// the device-side tool boundary.
    static let adapterSystemPrompt =
        "You are the agent brain running on OpenClaw. Tool names prefixed with \"minis_\" are "
        + "provided by the user's current iPhone (OpenMinis) and execute on-device; call them with "
        + "valid JSON arguments and wait for their results in the following turn. Handle every other "
        + "tool host-side as usual. You own identity, memory and context."

    /// Builds the complete wire message array for one turn: the fixed adapter
    /// policy followed by the current turn's delta only. Shared by `stream()`
    /// and the unit tests.
    static func wireMessages(_ messages: [AgentMessage]) -> [[String: Any]] {
        var result = convertMessages(currentTurnDelta(messages))
        result.insert(["role": "system", "content": adapterSystemPrompt], at: 0)
        return result
    }

    /// The minimum payload for one OpenClaw turn. OpenClaw routes the stable
    /// `user` session key to a persistent agent session, so re-sending OpenMinis'
    /// accumulated history would duplicate every old turn inside that session.
    /// A normal turn sends only its latest user message; a client-tool follow-up
    /// sends the assistant tool-call message plus its matching `role: tool`
    /// results so OpenClaw can correlate the call.
    static func currentTurnDelta(_ messages: [AgentMessage]) -> [AgentMessage] {
        guard let last = messages.last else { return [] }
        let isToolFollowUp = last.role == .user && last.parts.contains { part in
            if case .toolResult = part { return true } else { return false }
        }
        if isToolFollowUp,
           let assistantIndex = messages.dropLast().lastIndex(where: { $0.role == .assistant }) {
            return Array(messages[assistantIndex...])
        }
        return [last]
    }

    /// Converts OpenMinis agent history into OpenAI Chat Completions messages.
    /// Tool results ride as separate `role: "tool"` messages; images become
    /// `image_url` content parts. Shared by the adapter and the unit tests.
    static func convertMessages(_ messages: [AgentMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for msg in messages {
            let toolResults = msg.parts.compactMap { part -> (id: String, content: String, imageData: Data?, imageMime: String?)? in
                if case .toolResult(let id, _, let content, _, let imageData, let imageMime, _, _) = part {
                    return (id, content, imageData, imageMime)
                }
                return nil
            }
            if !toolResults.isEmpty {
                for tr in toolResults {
                    result.append([
                        "role": "tool",
                        "tool_call_id": sanitizeToolId(tr.id),
                        "content": tr.content,
                    ])
                    if let data = tr.imageData {
                        let mime = tr.imageMime ?? "image/jpeg"
                        result.append([
                            "role": "user",
                            "content": [[
                                "type": "image_url",
                                "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"],
                            ]],
                        ])
                    }
                }
                continue
            }

            switch msg.role {
            case .user:
                var parts: [[String: Any]] = []
                for part in msg.parts {
                    switch part {
                    case .text(let text):
                        parts.append(["type": "text", "text": text])
                    case .imageData(let data, let mimeType, _):
                        parts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:\(mimeType);base64,\(data.base64EncodedString())"],
                        ])
                    default:
                        break
                    }
                }
                result.append(["role": "user", "content": parts.isEmpty ? "" : parts])
            case .assistant:
                let text = msg.parts.compactMap { part -> String? in
                    if case .text(let t) = part { return t }
                    return nil
                }.joined()
                let toolUses = msg.parts.compactMap { part -> (String, String, [String: Any])? in
                    if case .toolUse(let id, let name, let input) = part { return (id, name, input) }
                    return nil
                }
                if toolUses.isEmpty && text.isEmpty {
                    continue  // nothing echoable — drop to avoid 400s
                }
                var assistant: [String: Any] = ["role": "assistant"]
                if !toolUses.isEmpty {
                    var toolCalls: [[String: Any]] = []
                    for (id, name, input) in toolUses {
                        let args = (try? JSONSerialization.data(withJSONObject: input))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        toolCalls.append([
                            "id": sanitizeToolId(id),
                            "type": "function",
                            "function": ["name": Self.encodedToolName(name), "arguments": args],
                        ])
                    }
                    assistant["tool_calls"] = toolCalls
                    if !text.isEmpty { assistant["content"] = text }
                } else {
                    assistant["content"] = text
                }
                result.append(assistant)
            }
        }
        return result
    }

    /// Converts OpenMinis tool definitions into OpenAI `tools` JSON. Shared by
    /// the adapter and the unit tests.
    static func convertTools(_ tools: [AgentToolDefinition]) -> [[String: Any]] {
        tools.map { tool in
            var properties: [String: Any] = [:]
            for (key, param) in tool.parameters {
                var schema: [String: Any] = ["type": param.type.rawValue]
                if !param.description.isEmpty { schema["description"] = param.description }
                if let enumValues = param.enumValues, !enumValues.isEmpty {
                    schema["enum"] = enumValues
                }
                properties[key] = schema
            }
            var parameters: [String: Any] = ["type": "object", "properties": properties]
            if !tool.required.isEmpty { parameters["required"] = tool.required }
            return [
                "type": "function",
                "function": [
                    "name": Self.encodedToolName(tool.name),
                    "description": tool.description,
                    "parameters": parameters,
                ],
            ]
        }
    }

    static func parseArgs(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return [:] }
        return dict
    }

    private static func ssePayload(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let after = line.dropFirst(5)
        if after.first == " " { return String(after.dropFirst()) }
        return String(after)
    }

    private static func jsonDict(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Session

    /// Long-lived streaming session, mirroring the raw-LLM providers' session
    /// (600s request timeout + network-transition connection-pool eviction).
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        let session = URLSession(configuration: config)
        LLMSessionRegistry.shared.register(session)
        return session
    }()
}
