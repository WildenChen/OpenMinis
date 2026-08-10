import Foundation

// ============================================================================
// Issue #9 wire-format validator.
//
// Compiles the REAL OpenClaw backend sources and validates the Location +
// Calendar `minis_*` roundtrip boundary end-to-end at the wire level:
//
//   1. Session continuity: soulnest:<chatID> key, A/B/A resume semantics.
//   2. Tool namespace: the real `makeAgentTools()` names map to `minis_*` and
//      back, injectively, without colliding with OpenClaw-native tools.
//   3. Location turn: gateway tool-call for `minis_shell_execute` decoding
//      `apple-location` → phone-side execution → `role: tool` follow-up.
//   4. Calendar turn: same for `apple-calendar list`.
//   5. New-chat isolation: only the current turn's delta is sent.
//
// This is evidence for the wire boundary of Issue #9; actual on-device
// execution and a real gateway roundtrip still require a physical iPhone.
// ============================================================================

var failures: [String] = []
func expect(_ cond: @autoclosure () -> Bool, _ label: String) {
    if cond() { print("  [PASS] \(label)") } else { failures.append(label); print("  [FAIL] \(label)") }
}

func userMsg(_ text: String) -> AgentMessage { AgentMessage(role: .user, parts: [.text(text)]) }
func assistantMsg(_ text: String) -> AgentMessage { AgentMessage(role: .assistant, parts: [.text(text)]) }
func assistantToolMsg(id: String, name: String, input: [String: Any]) -> AgentMessage {
    AgentMessage(role: .assistant, parts: [.toolUse(id: id, name: name, input: input)])
}
func toolResultMsg(id: String, content: String) -> AgentMessage {
    AgentMessage(role: .user, parts: [.toolResult(id: id, name: "shell_execute", content: content, isError: false)])
}

func stream(_ lines: [String]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

func collect(_ events: AsyncThrowingStream<AgentStreamEvent, Error>) async throws -> [AgentStreamEvent] {
    var result: [AgentStreamEvent] = []
    for try await event in events { result.append(event) }
    return result
}

// The real OpenMinis tool set as produced by `makeAgentTools()`.
let realToolNames = ["shell_execute", "file_read", "file_write", "file_edit", "browser_use", "memory_write", "memory_get", "read_image"]
let openClawNativeNames = ["web_search", "host_terminal", "screenshot", "browser_navigate", "claude", "shell"]

func run() async throws {
    print("== 1. Session continuity ==")
    let a1 = AgentBackendSession(openMinisSessionID: "chat-A").externalSessionKey
    let b1 = AgentBackendSession(openMinisSessionID: "chat-B").externalSessionKey
    expect(a1 == "soulnest:chat-A", "chat A maps to soulnest:chat-A")
    expect(b1 == "soulnest:chat-B", "chat B maps to soulnest:chat-B")
    expect(a1 != b1, "different chats get different backend sessions")
    expect(AgentBackendSession(openMinisSessionID: "chat-A").externalSessionKey == a1, "returning to chat A resumes its original session")
    expect(AgentBackendSession(openMinisSessionID: "chat-A").externalSessionKey == AgentBackendSession(openMinisSessionID: "chat-A").externalSessionKey, "follow-up turn in chat A keeps the same key")

    print("== 2. Tool namespace (real makeAgentTools names) ==")
    let wireNames = realToolNames.map(OpenClawBackend.encodedToolName)
    expect(wireNames.allSatisfy { $0.hasPrefix(OpenClawBackend.clientToolPrefix) }, "all OpenMinis tools are namespaced with minis_")
    expect(Set(wireNames).count == realToolNames.count, "namespace is injective (no client-tool collisions)")
    for (original, wire) in zip(realToolNames, wireNames) {
        expect(OpenClawBackend.decodedToolName(wire) == original, "decoded \(wire) == \(original)")
    }
    let collision = openClawNativeNames.first { wireNames.contains($0) }
    expect(collision == nil, "no OpenMinis wire name collides with an OpenClaw-native tool")
    expect(OpenClawBackend.decodedToolName("web_search") == "web_search", "OpenClaw-native names pass through unchanged")

    print("== 3. Location turn (apple-location) ==")
    let locationCommand = "apple-location"
    let realTools = realToolNames.map {
        AgentToolDefinition(name: $0, description: "tool \($0)", parameters: ["tool_title": AgentToolParam(type: .string, description: "t")], required: ["tool_title"])
    }
    let convertedTools = OpenClawBackend.convertTools(realTools)
    let shellWire = convertedTools.first { (($0["function"] as? [String: Any])?["name"] as? String) == "minis_shell_execute" }
    expect(shellWire != nil, "shell_execute is advertised on the wire as minis_shell_execute")
    expect(convertedTools.allSatisfy { ($0["type"] as? String) == "function" }, "all wire tools are type=function")

    let turn1 = OpenClawBackend.wireMessages([userMsg("Where am I?")])
    expect(turn1.count == 2 && (turn1[0]["role"] as? String) == "system", "turn 1 = fixed adapter policy + user message")
    let u0 = turn1[1]["content"] as? [[String: Any]]
    expect(u0?.first?["text"] as? String == "Where am I?", "turn 1 carries only the current user message")

    let locEvents = try await collect(OpenClawBackend.parseSSE(stream([
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_loc","function":{"name":"minis_shell_execute","arguments":"{\"tool_title\":\"Get current location\",\"command\":\"apple-location\"}"}}]}}]}"#,
        #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
    ])))
    guard case .toolCallComplete(let locID, let locName, let locArgs, _) = locEvents.last(where: { if case .toolCallComplete = $0 { return true } else { return false } }) else {
        return expect(false, "location tool call parsed")
    }
    expect(locName == "shell_execute", "decoded minis_shell_execute back to shell_execute (got \(locName))")
    expect(locArgs["command"] as? String == locationCommand, "location command preserved (got \(locArgs["command"] ?? ""))")

    let locationJSON = "{\"ok\":true,\"lat\":37.7749,\"lng\":-122.4194,\"accuracy\":65,\"status\":\"mock-for-validator\"}"
    let followUp = OpenClawBackend.currentTurnDelta([
        userMsg("Where am I?"),
        assistantToolMsg(id: locID, name: locName, input: locArgs),
        toolResultMsg(id: locID, content: locationJSON),
    ])
    expect(followUp.count == 2 && followUp[0].role == .assistant && followUp[1].role == .user, "tool follow-up delta = assistant call + role:tool result")
    let followWire = OpenClawBackend.convertMessages(followUp)
    expect(followWire.count == 2, "follow-up converts to exactly assistant + tool messages")
    expect((followWire[0]["role"] as? String) == "assistant", "follow-up[0] role == assistant")
    let tc = (followWire[0]["tool_calls"] as? [[String: Any]])?.first
    expect(tc?["id"] as? String == locID, "tool_call id preserved")
    let fn = tc?["function"] as? [String: Any]
    expect(fn?["name"] as? String == "minis_shell_execute", "assistant tool_call re-encoded to minis_shell_execute")
    let args = (fn?["arguments"] as? String ?? "").data(using: .utf8)
    let argsObj = args.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    expect(argsObj?["command"] as? String == locationCommand, "assistant tool_call arguments keep the apple-location command")
    expect((followWire[1]["role"] as? String) == "tool", "follow-up[1] role == tool")
    expect((followWire[1]["tool_call_id"] as? String) == locID, "tool result links to the same tool_call id")
    expect((followWire[1]["content"] as? String) == locationJSON, "tool result carries the offload JSON verbatim")
    let locFullWire = OpenClawBackend.wireMessages([
        userMsg("Where am I?"),
        assistantToolMsg(id: locID, name: locName, input: locArgs),
        toolResultMsg(id: locID, content: locationJSON),
    ])
    expect(locFullWire.count == 3 && (locFullWire[0]["role"] as? String) == "system", "location follow-up = system + assistant + tool")

    print("== 4. Calendar turn (apple-calendar list --today) ==")
    let calendarCommand = "apple-calendar list --today"
    let calEvents = try await collect(OpenClawBackend.parseSSE(stream([
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_cal","function":{"name":"minis_shell_execute","arguments":"{\"tool_title\":\"Show today's events\",\"command\":\"apple-calendar list --today\"}"}}]}}]}"#,
        #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
    ])))
    guard case .toolCallComplete(let calID, let calName, let calArgs, _) = calEvents.last(where: { if case .toolCallComplete = $0 { return true } else { return false } }) else {
        return expect(false, "calendar tool call parsed")
    }
    expect(calName == "shell_execute", "calendar tool call decodes to shell_execute")
    expect(calArgs["command"] as? String == calendarCommand, "calendar command preserved")

    let calJSON = "{\"ok\":true,\"events\":[{\"title\":\"Team sync\",\"start\":\"2026-08-10T09:00:00Z\",\"status\":\"mock-for-validator\"}]}"
    let calFollowWire = OpenClawBackend.wireMessages([
        userMsg("What is on my calendar today?"),
        assistantToolMsg(id: calID, name: calName, input: calArgs),
        toolResultMsg(id: calID, content: calJSON),
    ])
    expect(calFollowWire.count == 3, "calendar follow-up = system + assistant + tool")
    expect((calFollowWire[2]["role"] as? String) == "tool" && (calFollowWire[2]["tool_call_id"] as? String) == calID, "calendar tool result rides as role:tool with matching id")
    expect((calFollowWire[2]["content"] as? String) == calJSON, "calendar offload JSON preserved verbatim")

    print("== 5. New-chat isolation (no full-history replay) ==")
    let newChatTurn = OpenClawBackend.wireMessages([
        userMsg("old chat A content"),
        assistantMsg("I am in SF."),
        userMsg("This is chat B's next message"),
    ])
    expect(newChatTurn.count == 2, "new chat turn sends only system + latest user message")
    let nb = newChatTurn[1]["content"] as? [[String: Any]]
    expect(nb?.first?["text"] as? String == "This is chat B's next message", "no old-turn replay across chats")
    let chatBKey = AgentBackendSession(openMinisSessionID: "chat-B").externalSessionKey
    expect(chatBKey == "soulnest:chat-B", "chat B carries its own session key on every turn")

    print("== 6. Provider bridging (session-aware) ==")
    let recording = RecordingBackend()
    let provider = AgentBackendProvider(backend: recording)
    let stream = try await provider.streamAgentMessageClamped(
        sessionID: "chat-xyz",
        messages: [userMsg("hi")],
        systemPrompt: nil,
        tools: [],
        maxTokens: 0,
        thinkingLevel: .off
    )
    for try await _ in stream {}
    expect(recording.capturedSession?.externalSessionKey == "soulnest:chat-xyz", "provider forwards sessionID into the backend request")
    expect(recording.capturedMessages.count == 1, "provider forwards the agent messages")
    do {
        _ = try await provider.streamAgentMessageClamped(
            messages: [userMsg("hi")], systemPrompt: nil, tools: [], maxTokens: 0, thinkingLevel: .off
        )
        expect(false, "provider without sessionID should throw")
    } catch {
        guard case AgentBackendError.missingSessionID = error else { return expect(false, "expected missingSessionID") }
        expect(true, "provider without sessionID throws missingSessionID")
    }
}

private final class RecordingBackend: ExternalAgentBackend, @unchecked Sendable {
    var capturedSession: AgentBackendSession?
    var capturedMessages: [AgentMessage] = []
    var name: String { "Recording" }
    var model: LLMModel { OpenClawBackend.defaultModel }
    var defaultMaxTokens: Int { 256 }
    func stream(request: AgentBackendRequest) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        capturedSession = request.session
        capturedMessages = request.messages
        return AsyncThrowingStream { continuation in continuation.finish() }
    }
}

do {
    try await run()
    print(failures.isEmpty ? "\nALL CHECKS PASSED" : "\n\(failures.count) CHECK(S) FAILED")
    exit(failures.isEmpty ? 0 : 1)
} catch {
    print("HARNESS ERROR: \(error)")
    exit(2)
}
