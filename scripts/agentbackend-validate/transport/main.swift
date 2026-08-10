import Foundation

// Transport-level validation of OpenClawBackend.stream() against a local mock
// OpenAI-compatible gateway. Exercises the real URLSession + SSE path including
// Authorization / x-openclaw-agent-id headers and the request body shape.

var failures: [String] = []
func expect(_ cond: @autoclosure () -> Bool, _ label: String) {
    if cond() { print("  [PASS] \(label)") } else { failures.append(label); print("  [FAIL] \(label)") }
}

let mockBase = URL(string: "http://127.0.0.1:\(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "18990")")!
let config = OpenClawBackendConfig(
    baseURL: mockBase,
    agentID: "yujie",
    gatewayToken: "test-gateway-token"
)
let backend = OpenClawBackend(config: config)
let session = AgentBackendSession(openMinisSessionID: "chat-xyz")

func streamTurn(messages: [AgentMessage], tools: [AgentToolDefinition], maxTokens: Int) async throws -> [AgentStreamEvent] {
    var events: [AgentStreamEvent] = []
    let s = try await backend.stream(request: AgentBackendRequest(
        session: session,
        messages: messages,
        systemPrompt: nil,
        tools: tools,
        maxTokens: maxTokens,
        thinkingLevel: .off
    ))
    for try await e in s { events.append(e) }
    return events
}

func toolDefinitions() -> [AgentToolDefinition] {
    [
        AgentToolDefinition(
            name: "shell_execute",
            description: "Execute a command in an isolated Linux process",
            parameters: [
                "tool_title": AgentToolParam(type: .string, description: "Summary"),
                "command": AgentToolParam(type: .string, description: "The shell command"),
                "timeout": AgentToolParam(type: .integer, description: "Seconds"),
            ],
            required: ["tool_title", "command"]
        )
    ]
}

do {
    print("== Turn 1: user question -> gateway tool call ==")
    let turn1 = try await streamTurn(
        messages: [AgentMessage(role: .user, parts: [.text("Where am I?")])],
        tools: toolDefinitions(),
        maxTokens: 4096
    )
    let completes = turn1.compactMap { e -> (String, String, [String: Any])? in
        if case .toolCallComplete(let id, let name, let args, _) = e { return (id, name, args) }
        return nil
    }
    expect(completes.count == 1, "one tool call completed (got \(completes.count))")
    if let c = completes.first {
        expect(c.0 == "call_abc", "tool_call id == call_abc (got \(c.0))")
        expect(c.1 == "shell_execute", "minis_shell_execute decoded to shell_execute (got \(c.1))")
        expect(c.2["command"] as? String == "apple-location", "command == apple-location (got \(c.2["command"] ?? ""))")
    }
    expect(turn1.last != nil, "stream produced a final event")
    if case .done(let reason)? = turn1.last {
        switch reason {
        case .toolUse: print("  [PASS] final event == done(.toolUse)")
        default: failures.append("final event should be done(.toolUse)"); print("  [FAIL] final event was done(\(reason))")
        }
    }

    print("== Turn 2: phone tool result -> final answer ==")
    let locationJSON = "{\"ok\":true,\"lat\":37.7749,\"lng\":-122.4194,\"accuracy\":65,\"status\":\"mock-for-validator\"}"
    let turn2 = try await streamTurn(
        messages: [
            AgentMessage(role: .assistant, parts: [.toolUse(id: "call_abc", name: "shell_execute", input: [
                "tool_title": "Get current location", "command": "apple-location",
            ])]),
            AgentMessage(role: .user, parts: [.toolResult(id: "call_abc", name: "shell_execute", content: locationJSON, isError: false)]),
        ],
        tools: toolDefinitions(),
        maxTokens: 4096
    )
    var text = ""
    for e in turn2 { if case .textDelta(let t) = e { text += t } }
    expect(text == "You are at the Golden Gate Bridge.", "final answer text received (got \(text))")
    if case .done(.endTurn)? = turn2.last {
        print("  [PASS] turn 2 ends with done(.endTurn)")
    } else {
        failures.append("turn 2 should end with done(.endTurn)"); print("  [FAIL] turn 2 final event was \(String(describing: turn2.last))")
    }

    print(failures.isEmpty ? "\nALL TRANSPORT CHECKS PASSED" : "\n\(failures.count) TRANSPORT CHECK(S) FAILED")
    exit(failures.isEmpty ? 0 : 1)
} catch {
    print("TRANSPORT HARNESS ERROR: \(error)")
    exit(2)
}
