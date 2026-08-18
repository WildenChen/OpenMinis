import XCTest
@testable import Minis

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

    func testRequestUsesExplicitOpenClawSessionHeaderAndKeepsUser() throws {
        let session = AgentBackendSession(openMinisSessionID: "chat-A")
        let request = try OpenClawBackend.urlRequest(
            config: OpenClawBackendConfig(
                baseURL: URL(string: "https://openclaw.example")!,
                agentID: "yujie",
                gatewayToken: "test-token"
            ),
            session: session,
            body: ["user": session.externalSessionKey]
        )

        XCTAssertEqual(request.url?.absoluteString, "https://openclaw.example/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-openclaw-session-key"), "soulnest:chat-A")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-openclaw-agent-id"), "yujie")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])["user"] as? String, "soulnest:chat-A")
    }

    // MARK: - Hermes adapter (#6, #7, #21)

    func testHermesProfileEndpointAndStableSessionHeaders() throws {
        let request = AgentBackendRequest(
            session: AgentBackendSession(openMinisSessionID: "chat-A"),
            messages: [AgentMessage(role: .user, parts: [.text("Hello")])],
            systemPrompt: nil, tools: [], maxTokens: 123, thinkingLevel: .off
        )
        let urlRequest = try HermesBackend.urlRequest(
            endpoint: URL(string: "https://hermes.example")!, profileID: "xiaomi",
            credential: "test-token", model: HermesBackend.defaultModel, request: request
        )
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://hermes.example/p/xiaomi/v1/chat/completions")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Hermes-Session-Id"), "soulnest:chat-A")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Hermes-Session-Key"), "soulnest:chat-A")
        XCTAssertEqual(HermesBackend.chatURL(endpoint: URL(string: "https://hermes.example/v1/chat/completions")!, profileID: "ignored").path, "/v1/chat/completions")
    }

    func testHermesSessionIdentitySeparatesChatsAndSurvivesRetry() throws {
        func header(for chatID: String) throws -> String? {
            let request = AgentBackendRequest(session: AgentBackendSession(openMinisSessionID: chatID), messages: [], systemPrompt: nil, tools: [], maxTokens: 0, thinkingLevel: .off)
            return try HermesBackend.urlRequest(endpoint: URL(string: "https://hermes.example")!, profileID: nil, credential: "token", model: HermesBackend.defaultModel, request: request)
                .value(forHTTPHeaderField: "X-Hermes-Session-Id")
        }
        XCTAssertEqual(try header(for: "A"), "soulnest:A")
        XCTAssertEqual(try header(for: "B"), "soulnest:B")
        XCTAssertEqual(try header(for: "A"), "soulnest:A")
    }

    func testHermesRequestUsesCurrentTurnAndNoInventedToolProtocol() {
        let body = HermesBackend.body(for: AgentBackendRequest(
            session: AgentBackendSession(openMinisSessionID: "chat"),
            messages: [
                AgentMessage(role: .user, parts: [.text("old")]),
                AgentMessage(role: .assistant, parts: [.text("old response")]),
                AgentMessage(role: .user, parts: [.text("new")]),
            ],
            systemPrompt: nil,
            tools: [AgentToolDefinition(name: "location", description: "phone", parameters: [:], required: [])],
            maxTokens: 0, thinkingLevel: .off
        ), model: HermesBackend.defaultModel)
        XCTAssertNil(body["tools"])
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        let content = messages?.first?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["text"] as? String, "new")
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
        XCTAssertEqual(fn?["name"] as? String, "minis_web_search")
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
        XCTAssertEqual(fn?["name"] as? String, "minis_get_weather")
        XCTAssertEqual(fn?["description"] as? String, "Get weather for a city")
        let params = fn?["parameters"] as? [String: Any]
        XCTAssertEqual(params?["type"] as? String, "object")
        XCTAssertEqual(params?["required"] as? [String], ["city"])
        let city = (params?["properties"] as? [String: Any])?["city"] as? [String: Any]
        XCTAssertEqual(city?["type"] as? String, "string")
        XCTAssertEqual(city?["enum"] as? [String], ["SF", "NY"])
    }

    // MARK: - Tool name namespace

    func testToolNameNamespaceRoundtrip() {
        XCTAssertEqual(OpenClawBackend.encodedToolName("location"), "minis_location")
        XCTAssertEqual(OpenClawBackend.decodedToolName("minis_location"), "location")
        XCTAssertEqual(OpenClawBackend.decodedToolName(OpenClawBackend.encodedToolName("location")), "location")
    }

    func testToolNameNamespaceRoundtripWhenClientNameAlreadyPrefixed() {
        XCTAssertEqual(OpenClawBackend.encodedToolName("minis_foo"), "minis_minis_foo")
        XCTAssertEqual(OpenClawBackend.decodedToolName("minis_minis_foo"), "minis_foo")
        XCTAssertEqual(OpenClawBackend.decodedToolName(OpenClawBackend.encodedToolName("minis_foo")), "minis_foo")
    }

    func testToolNameNamespaceLeavesOpenClawNativeToolsUntouched() {
        XCTAssertEqual(OpenClawBackend.decodedToolName("web_search"), "web_search")
        XCTAssertEqual(OpenClawBackend.decodedToolName("screenshot"), "screenshot")
    }

    func testToolNameNamespaceIsInjectiveNoCollisions() {
        let names = ["location", "minis_location", "a", "minis_a", "calendar_list"]
        let wire = names.map(OpenClawBackend.encodedToolName)
        XCTAssertEqual(Set(wire).count, names.count)
        for (original, encoded) in zip(names, wire) {
            XCTAssertEqual(OpenClawBackend.decodedToolName(encoded), original)
        }
    }

    // MARK: - Current-turn delta (no full-history replay)

    private func userMsg(_ text: String) -> AgentMessage {
        AgentMessage(role: .user, parts: [.text(text)])
    }

    private func assistantMsg(_ text: String) -> AgentMessage {
        AgentMessage(role: .assistant, parts: [.text(text)])
    }

    private func assistantToolMsg(id: String, name: String, input: [String: Any]) -> AgentMessage {
        AgentMessage(role: .assistant, parts: [.toolUse(id: id, name: name, input: input)])
    }

    private func toolResultMsg(id: String, content: String) -> AgentMessage {
        AgentMessage(role: .user, parts: [.toolResult(id: id, name: "x", content: content, isError: false)])
    }

    func testCurrentTurnDeltaNormalTurnSendsOnlyLatestUserMessage() {
        let delta = OpenClawBackend.currentTurnDelta([
            userMsg("where are you"),
            assistantMsg("I am in SF."),
            userMsg("what's the weather?"),
        ])
        XCTAssertEqual(delta.count, 1)
        guard case .text("what's the weather?") = delta[0].parts.first else {
            return XCTFail("expected only the latest user message")
        }
    }

    func testCurrentTurnDeltaFirstTurnSendsTheOnlyMessage() {
        let delta = OpenClawBackend.currentTurnDelta([userMsg("hi")])
        XCTAssertEqual(delta.count, 1)
    }

    func testCurrentTurnDeltaToolFollowUpPairsAssistantCallWithResults() {
        let delta = OpenClawBackend.currentTurnDelta([
            userMsg("weather in SF"),
            assistantToolMsg(id: "call_1", name: "location", input: ["city": "SF"]),
            toolResultMsg(id: "call_1", content: "sunny"),
        ])
        XCTAssertEqual(delta.count, 2)
        XCTAssertEqual(delta[0].role, .assistant)
        XCTAssertEqual(delta[1].role, .user)
    }

    func testWireMessagesMultiTurnNeverReplaysOldTurns() {
        let turn1 = OpenClawBackend.wireMessages([userMsg("where are you")])
        XCTAssertEqual(turn1.count, 2)  // adapter system policy + one user message
        XCTAssertEqual(turn1[1]["role"] as? String, "user")

        let turn2 = OpenClawBackend.wireMessages([
            userMsg("where are you"),
            assistantMsg("I am in SF."),
            userMsg("what's the weather?"),
        ])
        XCTAssertEqual(turn2.count, 2)
        let content = turn2[1]["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["text"] as? String, "what's the weather?")
    }

    func testWireMessagesToolFollowUpCarriesOnlyCallAndResults() {
        let wire = OpenClawBackend.wireMessages([
            userMsg("weather in SF"),
            assistantToolMsg(id: "call_1", name: "location", input: ["city": "SF"]),
            toolResultMsg(id: "call_1", content: "sunny"),
        ])
        XCTAssertEqual(wire.count, 3)  // system policy + assistant tool_calls + role:tool result
        XCTAssertEqual(wire[0]["role"] as? String, "system")
        XCTAssertEqual(wire[1]["role"] as? String, "assistant")
        let toolCalls = wire[1]["tool_calls"] as? [[String: Any]]
        let fn = toolCalls?.first?["function"] as? [String: Any]
        XCTAssertEqual(fn?["name"] as? String, "minis_location")
        XCTAssertEqual(wire[2]["role"] as? String, "tool")
        XCTAssertEqual(wire[2]["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(wire[2]["content"] as? String, "sunny")
    }

    func testWireMessagesUsesFixedAdapterPolicyNotForwardedSystemPrompt() {
        let wire = OpenClawBackend.wireMessages([userMsg("hi")])
        XCTAssertEqual(wire.first?["role"] as? String, "system")
        XCTAssertEqual(wire.first?["content"] as? String, OpenClawBackend.adapterSystemPrompt)
        let systemMessages = wire.filter { ($0["role"] as? String) == "system" }
        XCTAssertEqual(systemMessages.count, 1)
    }

    func testAdapterPolicyAdvertisesNativeOffloadsThroughExistingShellTool() {
        let policy = OpenClawBackend.adapterSystemPrompt
        XCTAssertTrue(policy.contains("minis_shell_execute"))
        for capability in [
            "apple-location",
            "apple-calendar",
            "apple-photos",
            "apple-healthkit",
            "apple-homekit",
        ] {
            XCTAssertTrue(policy.contains(capability), "missing \(capability)")
        }
        XCTAssertFalse(policy.contains("minis_apple-"))
    }

    func testSessionContinuityABReturnA() {
        let a1 = AgentBackendSession(openMinisSessionID: "chat-A").externalSessionKey
        let b1 = AgentBackendSession(openMinisSessionID: "chat-B").externalSessionKey
        XCTAssertEqual(a1, "soulnest:chat-A")
        XCTAssertEqual(b1, "soulnest:chat-B")
        XCTAssertNotEqual(a1, b1)
        // Returning to chat A resumes its original backend session.
        XCTAssertEqual(AgentBackendSession(openMinisSessionID: "chat-A").externalSessionKey, a1)
        // A follow-up turn in chat A still carries the same session key.
        XCTAssertEqual(AgentBackendSession(openMinisSessionID: "chat-A").externalSessionKey, a1)
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

    func testParseSSEDecodesNamespacedClientToolCall() async throws {
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"minis_get_weather","arguments":"{\"city\":\"SF\"}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        ])))
        guard case .toolInputDelta(let streamName, _) = events[0] else {
            return XCTFail("expected toolInputDelta")
        }
        XCTAssertEqual(streamName, "get_weather")
        guard case .toolCallComplete(_, let name, _, _) = events[1] else {
            return XCTFail("expected toolCallComplete")
        }
        XCTAssertEqual(name, "get_weather")
    }

    func testParseSSELeavesOpenClawNativeToolCallNameUntouched() async throws {
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_9","function":{"name":"host_terminal","arguments":"{}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        ])))
        guard case .toolCallComplete(_, let name, _, _) = events[1] else {
            return XCTFail("expected toolCallComplete")
        }
        XCTAssertEqual(name, "host_terminal")
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

    func testParseSSEToolCallWithDoneMarkerOnlyStillCompletes() async throws {
        // A gateway may end the tool-call stream with `data: [DONE]` and omit
        // the final `finish_reason: "tool_calls"` chunk. The accumulated call
        // must still be flushed, not silently dropped (the drop turned into an
        // endless empty-response retry).
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"minis_get_location","arguments":"{\"accuracy\":\"high\"}"}}]}}]}"#,
            "data: [DONE]",
        ])))
        XCTAssertEqual(events.count, 3)
        guard case .toolInputDelta(let streamName, _) = events[0] else {
            return XCTFail("expected toolInputDelta first")
        }
        XCTAssertEqual(streamName, "get_location")
        guard case .toolCallComplete(_, let name, let args, _) = events[1] else {
            return XCTFail("expected toolCallComplete")
        }
        XCTAssertEqual(name, "get_location")
        XCTAssertEqual(args["accuracy"] as? String, "high")
        guard case .done(.toolUse) = events[2] else {
            return XCTFail("expected done(.toolUse)")
        }
    }

    // MARK: - Tool roundtrip (#9)

    /// Runs the full OpenClaw → OpenMinis → OpenClaw cycle for one device tool
    /// call: decodes the SSE tool call the way the agent loop does (Phase 1),
    /// builds the `agentHistory` the loop would hold after executing the tool
    /// on-device, then re-encodes the follow-up wire messages (Phase 2).
    /// Asserts the decode half produced a decoded name + `done(.toolUse)`.
    private func roundtripHistory(
        sseLines: [String],
        resultContent: String
    ) async throws -> [AgentMessage] {
        let events = try await collect(OpenClawBackend.parseSSE(stream(sseLines)))
        var decodedID: String?
        var decodedName: String?
        var decodedArgs: [String: Any] = [:]
        var doneSeen = false
        for event in events {
            switch event {
            case .toolCallComplete(let id, let name, let args, _):
                decodedID = id
                decodedName = name
                decodedArgs = args
            case .done(let reason):
                if case .toolUse = reason { doneSeen = true }
            default:
                break
            }
        }
        guard let decodedID, let decodedName, doneSeen else {
            XCTFail("expected a decoded device tool call + done(.toolUse)")
            return []
        }
        return [
            AgentMessage(role: .user, parts: [.text("please use the device tool")]),
            AgentMessage(role: .assistant, parts: [.toolUse(id: decodedID, name: decodedName, input: decodedArgs)]),
            AgentMessage(role: .user, parts: [.toolResult(id: decodedID, name: decodedName, content: resultContent, isError: false)]),
        ]
    }

    func testToolRoundtripLocationDeviceCall() async throws {
        let history = try await roundtripHistory(
            sseLines: [
                #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_loc","function":{"name":"minis_get_location","arguments":"{\"accuracy\":\"high\"}"}}]}}]}"#,
                #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            ],
            resultContent: "37.7749, -122.4194 (Cupertino)"
        )
        let wire = OpenClawBackend.wireMessages(history)
        XCTAssertEqual(wire.count, 3)  // adapter system policy + assistant + role:tool
        let assistant = wire[1]
        XCTAssertEqual(assistant["role"] as? String, "assistant")
        let toolCalls = assistant["tool_calls"] as? [[String: Any]]
        let fn = toolCalls?.first?["function"] as? [String: Any]
        XCTAssertEqual(toolCalls?.first?["id"] as? String, "call_loc")
        XCTAssertEqual(fn?["name"] as? String, "minis_get_location")
        let tool = wire[2]
        XCTAssertEqual(tool["role"] as? String, "tool")
        XCTAssertEqual(tool["tool_call_id"] as? String, "call_loc")
        XCTAssertEqual(tool["content"] as? String, "37.7749, -122.4194 (Cupertino)")
    }

    func testToolRoundtripCalendarCreateEventDeviceCall() async throws {
        let history = try await roundtripHistory(
            sseLines: [
                #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_cal","function":{"name":"minis_calendar_create_event","arguments":"{\"title\":\"Dentist\"}"}}]}}]}"#,
                #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            ],
            resultContent: "Event created: Dentist at 2026-08-11 10:00"
        )
        let wire = OpenClawBackend.wireMessages(history)
        let fn = ((wire[1]["tool_calls"] as? [[String: Any]])?.first?["function"] as? [String: Any])
        XCTAssertEqual(fn?["name"] as? String, "minis_calendar_create_event")
        XCTAssertEqual(wire[2]["role"] as? String, "tool")
        XCTAssertEqual(wire[2]["tool_call_id"] as? String, "call_cal")
    }

    func testToolRoundtripToolCallIDSurvivesSanitization() async throws {
        // OpenClaw may hand back provider-ish ids containing `|`. The sanitized
        // form must be identical in the assistant `tool_calls` id and the
        // `role: tool` `tool_call_id` so the gateway can pair them (a mismatch
        // is an API 400).
        let history = try await roundtripHistory(
            sseLines: [
                #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc|fc_1","function":{"name":"minis_get_location","arguments":"{}"}}]}}]}"#,
                #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            ],
            resultContent: "San Francisco"
        )
        let wire = OpenClawBackend.wireMessages(history)
        let toolCallID = ((wire[1]["tool_calls"] as? [[String: Any]])?.first?["id"] as? String)
        XCTAssertEqual(toolCallID, "call_abc-fc_1")
        XCTAssertEqual(wire[2]["tool_call_id"] as? String, toolCallID)
    }

    func testToolRoundtripParallelDeviceCallsStayPaired() async throws {
        let events = try await collect(OpenClawBackend.parseSSE(stream([
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_a","function":{"name":"minis_get_location","arguments":"{}"}},{"index":1,"id":"call_b","function":{"name":"minis_calendar_list","arguments":"{}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        ])))
        var completed: [(String, String)] = []
        for event in events {
            if case .toolCallComplete(let id, let name, _, _) = event {
                completed.append((id, name))
            }
        }
        XCTAssertEqual(completed.map(\.0), ["call_a", "call_b"])
        XCTAssertEqual(completed.map(\.1), ["get_location", "calendar_list"])

        // The loop's history after on-device execution: one assistant message
        // with both tool_uses, then one user message with both tool_results
        // in the originating order (parallel tool dispatch preserves order).
        let history = [
            AgentMessage(role: .user, parts: [.text("what's around?")]),
            AgentMessage(role: .assistant, parts: [
                .toolUse(id: "call_a", name: "get_location", input: [:]),
                .toolUse(id: "call_b", name: "calendar_list", input: [:]),
            ]),
            AgentMessage(role: .user, parts: [
                .toolResult(id: "call_a", name: "get_location", content: "Cupertino", isError: false),
                .toolResult(id: "call_b", name: "calendar_list", content: "No events", isError: false),
            ]),
        ]
        let wire = OpenClawBackend.wireMessages(history)
        XCTAssertEqual(wire.count, 4)  // system + assistant + 2× role:tool
        let toolCalls = wire[1]["tool_calls"] as? [[String: Any]]
        XCTAssertEqual(toolCalls?.count, 2)
        let names = toolCalls?.compactMap { (($0["function"] as? [String: Any])?["name"] as? String) }
        XCTAssertEqual(names, ["minis_get_location", "minis_calendar_list"])
        XCTAssertEqual(wire[2]["role"] as? String, "tool")
        XCTAssertEqual(wire[2]["tool_call_id"] as? String, "call_a")
        XCTAssertEqual(wire[3]["role"] as? String, "tool")
        XCTAssertEqual(wire[3]["tool_call_id"] as? String, "call_b")
    }

    func testToolRoundtripMultiRoundSendsOnlyLatestPair() {
        // Two consecutive tool rounds already executed. The next OpenClaw turn
        // must re-send ONLY the round-2 assistant call + its result — round 1
        // stays in the OpenClaw session (no full-history replay).
        let delta = OpenClawBackend.currentTurnDelta([
            userMsg("plan my day"),
            assistantToolMsg(id: "call_1", name: "get_location", input: [:]),
            toolResultMsg(id: "call_1", content: "Cupertino"),
            assistantToolMsg(id: "call_2", name: "calendar_create_event", input: ["title": "Lunch"]),
            toolResultMsg(id: "call_2", content: "Created"),
        ])
        XCTAssertEqual(delta.count, 2)
        XCTAssertEqual(delta[0].role, .assistant)
        guard case .toolUse(let id, let name, _) = delta[0].parts.first else {
            return XCTFail("expected tool_use")
        }
        XCTAssertEqual(id, "call_2")
        XCTAssertEqual(name, "calendar_create_event")
        XCTAssertEqual(delta[1].role, .user)
    }

    func testToolRoundtripNewUserTurnAfterFinalAnswerSendsOnlyNewText() {
        // After the tool roundtrip converged to a final answer, the next user
        // turn is a plain text delta — no stale tool internals leak through.
        let delta = OpenClawBackend.currentTurnDelta([
            userMsg("plan my day"),
            assistantToolMsg(id: "call_1", name: "get_location", input: [:]),
            toolResultMsg(id: "call_1", content: "Cupertino"),
            assistantMsg("Here's your plan for the day."),
            userMsg("thanks!"),
        ])
        XCTAssertEqual(delta.count, 1)
        guard case .text("thanks!") = delta[0].parts.first else {
            return XCTFail("expected only the new user text")
        }
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
