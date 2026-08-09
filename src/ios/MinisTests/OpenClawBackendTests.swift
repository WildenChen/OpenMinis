import XCTest

/// Focused tests for the OpenClaw external agent backend adapter: session-key
/// mapping, wire-format conversion, and SSE parsing. Network/transport is not
/// exercised; the tests cover the pure functions shared by the adapter and the
/// chat loop's session-aware bridging.
final class OpenClawBackendTests: XCTestCase {

    // MARK: - Session continuity

    func testExternalSessionKeyDerivesFromOpenMinisChatID() {
        let session = AgentBackendSession(openMinisSessionID: "chat-abc-123")
        XCTAssertEqual(session.externalSessionKey, "soulnest:chat-abc-123")
        XCTAssertNotEqual(
            AgentBackendSession(openMinisSessionID: "chat-other").externalSessionKey,
            session.externalSessionKey
        )
    }

    // MARK: - Message conversion

    func testConvertMessagesUserText() {
        let msg = AgentMessage(role: .user, parts: [.text("Hello")])
        let converted = OpenClawBackend.convertMessages([msg])
        XCTAssertEqual(converted.count, 1)
        XCTAssertEqual(converted[0]["role"] as? String, "user")
        let content = converted[0]["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertEqual(content?.first?["text"] as? String, "Hello")
    }

    func testConvertMessagesUserImageBecomesDataURL() {
        let data = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let msg = AgentMessage(role: .user, parts: [.imageData(data: data, mimeType: "image/jpeg")])
        let converted = OpenClawBackend.convertMessages([msg])
        XCTAssertEqual(converted.count, 1)
        let content = converted[0]["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "image_url")
        let imageURL = content?.first?["image_url"] as? [String: Any]
        XCTAssertTrue((imageURL?["url"] as? String ?? "").hasPrefix("data:image/jpeg;base64,"))
    }

    func testConvertMessagesAssistantText() {
        let msg = AgentMessage(role: .assistant, parts: [.text("Hi there")])
        let converted = OpenClawBackend.convertMessages([msg])
        XCTAssertEqual(converted[0]["role"] as? String, "assistant")
        XCTAssertEqual(converted[0]["content"] as? String, "Hi there")
        XCTAssertNil(converted[0]["tool_calls"])
    }

    func testConvertMessagesAssistantToolUse() {
        let msg = AgentMessage(
            role: .assistant,
            parts: [.toolUse(id: "call_1|bad", name: "web_search", input: ["query": "weather"])]
        )
        let converted = OpenClawBackend.convertMessages([msg])
        XCTAssertEqual(converted[0]["role"] as? String, "assistant")
        let toolCalls = converted[0]["tool_calls"] as? [[String: Any]]
        XCTAssertEqual(toolCalls?.first?["id"] as? String, "call_1-bad")
        let fn = toolCalls?.first?["function"] as? [String: Any]
        XCTAssertEqual(fn?["name"] as? String, "web_search")
        XCTAssertEqual(fn?["arguments"] as? String, #"{"query":"weather"}"#)
    }

    func testConvertMessagesToolResultRidesSeparateToolRole() {
        let msg = AgentMessage(
            role: .user,
            parts: [.toolResult(id: "call_1", name: "web_search", content: "sunny", isError: false)]
        )
        let converted = OpenClawBackend.convertMessages([msg])
        XCTAssertEqual(converted.count, 1)
        XCTAssertEqual(converted[0]["role"] as? String, "tool")
        XCTAssertEqual(converted[0]["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(converted[0]["content"] as? String, "sunny")
    }

    func testConvertMessagesToolResultWithImageAppendsImageUserMessage() {
        let data = Data([0x01, 0x02, 0x03])
        let msg = AgentMessage(
            role: .user,
            parts: [.toolResult(
                id: "call_2",
                name: "read_image",
                content: "",
                isError: false,
                imageData: data,
                imageMimeType: "image/png"
            )]
        )
        let converted = OpenClawBackend.convertMessages([msg])
        XCTAssertEqual(converted.count, 2)
        XCTAssertEqual(converted[0]["role"] as? String, "tool")
        XCTAssertEqual(converted[1]["role"] as? String, "user")
        let content = converted[1]["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "image_url")
    }

    func testConvertMessagesDropsEmptyAssistant() {
        let msg = AgentMessage(role: .assistant, parts: [])
        XCTAssertTrue(OpenClawBackend.convertMessages([msg]).isEmpty)
    }

    // MARK: - Tool conversion

    func testConvertToolsSchema() {
        let tools = [
            AgentToolDefinition(
                name: "get_weather",
                description: "Get weather for a city",
                parameters: [
                    "city": AgentToolParam(type: .string, description: "City name", enumValues: ["SF", "NY"]),
                ],
                required: ["city"]
            )
        ]
        let converted = OpenClawBackend.convertTools(tools)
        XCTAssertEqual(converted.count, 1)
        XCTAssertEqual(converted[0]["type"] as? String, "function")
        let fn = converted[0]["function"] as? [String: Any]
        XCTAssertEqual(fn?["name"] as? String, "get_weather")
        XCTAssertEqual(fn?["description"] as? String, "Get weather for a city")
        let params = fn?["parameters"] as? [String: Any]
        XCTAssertEqual(params?["type"] as? String, "object")
        XCTAssertEqual(params?["required"] as? [String], ["city"])
        let city = (params?["properties"] as? [String: Any])?["city"] as? [String: Any]
        XCTAssertEqual(city?["type"] as? String, "string")
        XCTAssertEqual(city?["enum"] as? [String], ["SF", "NY"])
    }

    // MARK: - SSE parsing

    private func stream(_ lines: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for line in lines {
                    continuation.yield(line)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func collect(_ events: AsyncThrowingStream<AgentStreamEvent, Error>) async throws -> [AgentStreamEvent] {
        var result: [AgentStreamEvent] = []
        for try await event in events {
            result.append(event)
        }
        return result
    }

    func testParseSSETextStream() async throws {
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"lo"}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "data: [DONE]",
        ])))
        XCTAssertEqual(events.count, 4)
        guard case .contentBlockStart(.text) = events[0] else {
            return XCTFail("expected contentBlockStart")
        }
        guard case .textDelta("Hel") = events[1] else { return XCTFail("expected text 'Hel'") }
        guard case .textDelta("lo") = events[2] else { return XCTFail("expected text 'lo'") }
        guard case .done(.endTurn) = events[3] else { return XCTFail("expected done(.endTurn)") }
    }

    func testParseSSEToolCallStreamAccumulatesArguments() async throws {
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_weather","arguments":"{\"city\":\""}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"SF\"}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        ])))
        XCTAssertEqual(events.count, 4)
        guard case .toolInputDelta(let name, _) = events[0] else {
            return XCTFail("expected toolInputDelta")
        }
        XCTAssertEqual(name, "get_weather")
        guard case .toolInputDelta(_, _) = events[1] else {
            return XCTFail("expected second toolInputDelta")
        }
        guard case .toolCallComplete(let id, let name, let args, let metadata) = events[2] else {
            return XCTFail("expected toolCallComplete")
        }
        XCTAssertEqual(id, "call_1")
        XCTAssertEqual(name, "get_weather")
        XCTAssertEqual(args["city"] as? String, "SF")
        XCTAssertNil(metadata)
        guard case .done(.toolUse) = events[3] else {
            return XCTFail("expected done(.toolUse)")
        }
    }

    func testParseSSESkipsHeartbeatsAndReadsUsage() async throws {
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            ": keep-alive",
            "",
            "data: {}",
            #"data: {"usage":{"prompt_tokens":10,"completion_tokens":5}}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
        ])))
        XCTAssertEqual(events.count, 2)
        guard case .usage(let usage) = events[0] else {
            return XCTFail("expected usage event")
        }
        XCTAssertEqual(usage.inputTokens, 10)
        XCTAssertEqual(usage.outputTokens, 5)
        guard case .done(.endTurn) = events[1] else {
            return XCTFail("expected done(.endTurn)")
        }
    }

    func testParseSSEFinishOnlyChunkWithoutDeltaStillEndsTurn() async throws {
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            #"data: {"choices":[{"finish_reason":"stop"}]}"#,
        ])))
        XCTAssertEqual(events.count, 1)
        guard case .done(.endTurn) = events[0] else {
            return XCTFail("expected done(.endTurn)")
        }
    }

    func testParseSSELengthFinishMapsToMaxTokens() async throws {
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#,
        ])))
        XCTAssertEqual(events.count, 1)
        guard case .done(.maxTokens) = events[0] else {
            return XCTFail("expected done(.maxTokens)")
        }
    }

    func testParseSSEDoneMarkerAloneEndsTurn() async throws {
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            "data: [DONE]",
        ])))
        XCTAssertEqual(events.count, 1)
        guard case .done(.endTurn) = events[0] else {
            return XCTFail("expected done(.endTurn)")
        }
    }

    func testParseArgsInvalidJSONReturnsEmpty() {
        XCTAssertTrue(OpenClawBackend.parseArgs("{not json").isEmpty)
    }

    // MARK: - Provider bridging

    func testProviderBridgesSessionIDToBackendRequest() async throws {
        let backend = RecordingBackend()
        let provider = AgentBackendProvider(backend: backend)
        let stream = try await provider.streamAgentMessageClamped(
            sessionID: "chat-xyz",
            messages: [AgentMessage(role: .user, parts: [.text("hi")])],
            systemPrompt: nil,
            tools: [],
            maxTokens: 0,
            thinkingLevel: .off
        )
        for try await _ in stream {}
        XCTAssertEqual(backend.capturedSession, AgentBackendSession(openMinisSessionID: "chat-xyz"))
        XCTAssertEqual(backend.capturedMessages.count, 1)
    }

    func testProviderWithoutSessionIDThrows() async {
        let provider = AgentBackendProvider(backend: RecordingBackend())
        do {
            _ = try await provider.streamAgentMessageClamped(
                messages: [AgentMessage(role: .user, parts: [.text("hi")])],
                systemPrompt: nil,
                tools: [],
                maxTokens: 0,
                thinkingLevel: .off
            )
            XCTFail("expected missingSessionID error")
        } catch {
            guard case AgentBackendError.missingSessionID = error else {
                return XCTFail("expected missingSessionID, got \(error)")
            }
        }
    }

    // MARK: - Registry + active state

    @MainActor
    func testActiveStateResolvesConfiguredOpenClawBackend() {
        AgentBackendRegistry.registerOpenClaw()
        AgentBackendConfigStore.setActive(AgentBackendConfig(backendID: "openclaw", agentID: "yujie"))
        defer { AgentBackendConfigStore.setActive(nil) }

        guard let resolved = AgentBackendActiveState.resolved() else {
            return XCTFail("expected resolved backend")
        }
        XCTAssertEqual(resolved.provider.name, "OpenClaw")
        XCTAssertEqual(resolved.entry.providerInstanceId, AgentBackendActiveState.syntheticProviderInstanceId)
        XCTAssertEqual(resolved.entry.model.displayName, "OpenClaw")
        XCTAssertTrue(AgentBackendActiveState.isBackendEntry(resolved.entry))
    }

    @MainActor
    func testActiveStateNilWhenNoBackendConfigured() {
        AgentBackendConfigStore.setActive(nil)
        XCTAssertNil(AgentBackendActiveState.resolved())
    }
}

/// Test-only backend that records the request instead of touching the network.
private final class RecordingBackend: ExternalAgentBackend, @unchecked Sendable {
    var capturedSession: AgentBackendSession?
    var capturedMessages: [AgentMessage] = []

    var name: String { "Recording" }
    var model: LLMModel { OpenClawBackend.defaultModel }
    var defaultMaxTokens: Int { 256 }

    func stream(request: AgentBackendRequest) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        capturedSession = request.session
        capturedMessages = request.messages
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
