import Foundation

// Live two-turn probe of OpenClawBackend against a REAL OpenClaw gateway.
// Token comes from the environment (never argv, never persisted).
// Turn 1 sends the canonical OpenMinis tool set (namespaced to minis_*) and the
// user session key soulnest:<chat>. If the agent responds with a
// minis_shell_execute tool call, Turn 2 feeds back a simulated phone-side
// result (location offload JSON) through the same session key and prints the
// final answer.
//
// Env: OPENCLAW_BASE_URL (required), OPENCLAW_GATEWAY_TOKEN (required unless the
// gateway disables auth), OPENCLAW_AGENT_ID (default "yujie").

var failures: [String] = []
func expect(_ cond: @autoclosure () -> Bool, _ label: String) {
    if cond() { print("  [PASS] \(label)") } else { failures.append(label); print("  [FAIL] \(label)") }
}

guard let baseEnv = ProcessInfo.processInfo.environment["OPENCLAW_BASE_URL"],
      let baseURL = URL(string: baseEnv) else {
    print("REQUIRED ENV: OPENCLAW_BASE_URL (and optionally OPENCLAW_GATEWAY_TOKEN, OPENCLAW_AGENT_ID)")
    exit(2)
}
let token = ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_TOKEN"] ?? ""
let agentID = ProcessInfo.processInfo.environment["OPENCLAW_AGENT_ID"] ?? "yujie"

let backend = OpenClawBackend(config: OpenClawBackendConfig(
    baseURL: baseURL, agentID: agentID, gatewayToken: token.isEmpty ? nil : token
))
let session = AgentBackendSession(openMinisSessionID: "soulnest-e2e-validator-001")

func realTools() -> [AgentToolDefinition] {
    func t(_ name: String, _ desc: String, _ params: [(String, AgentParamType, String)], required: [String]) -> AgentToolDefinition {
        AgentToolDefinition(
            name: name, description: desc,
            parameters: Dictionary(uniqueKeysWithValues: params.map { ($0.0, AgentToolParam(type: $0.1, description: $0.2)) }),
            required: required
        )
    }
    return [
        t("shell_execute", "Execute a command in an isolated Linux process (iSH/Alpine).",
          [("tool_title", .string, "5-10 word summary"), ("command", .string, "The shell command to execute"),
           ("timeout", .integer, "Timeout in seconds (default: 900)"), ("delay", .integer, "Delay in seconds")],
          required: ["tool_title", "command"]),
        t("file_read", "Read a file from the Linux filesystem.",
          [("tool_title", .string, "summary"), ("path", .string, "Absolute Linux path"), ("offset", .integer, "start line"),
           ("lines", .integer, "max lines"), ("max_length", .integer, "max chars"), ("direction", .string, "head|tail")],
          required: ["tool_title", "path"]),
        t("file_write", "Write content to a file on the Linux filesystem.",
          [("tool_title", .string, "summary"), ("path", .string, "Absolute Linux path"), ("content", .string, "text content"),
           ("append", .boolean, "append instead of overwrite"), ("create_dirs", .boolean, "create parents")],
          required: ["tool_title", "path", "content"]),
        t("file_edit", "Make targeted edits to an existing file.",
          [("tool_title", .string, "summary"), ("path", .string, "Absolute Linux path"), ("old_string", .string, "text to replace"),
           ("new_string", .string, "replacement"), ("replace_all", .boolean, "replace all occurrences")],
          required: ["tool_title", "path", "old_string", "new_string"]),
        t("browser_use", "Control a web browser.",
          [("tool_title", .string, "summary"), ("action", .string, "browser action"), ("url", .string, "URL")],
          required: ["tool_title", "action"]),
        t("memory_write", "Write a memory entry to today's daily log.",
          [("tool_title", .string, "summary"), ("content", .string, "memory content")],
          required: ["tool_title", "content"]),
        t("memory_get", "Retrieve memories from persistent storage.",
          [("tool_title", .string, "summary"), ("scope", .string, "daily|all"), ("keywords", .string, "search keywords")],
          required: ["tool_title"]),
        t("read_image", "Read an image file and return it for visual analysis.",
          [("tool_title", .string, "summary"), ("path", .string, "Linux path")],
          required: ["tool_title", "path"]),
    ]
}

func collect(messages: [AgentMessage], tools: [AgentToolDefinition], maxTokens: Int) async throws -> (events: [AgentStreamEvent], raw: String) {
    let stream = try await backend.stream(request: AgentBackendRequest(
        session: session, messages: messages, systemPrompt: nil,
        tools: tools, maxTokens: maxTokens, thinkingLevel: .off
    ))
    return try await withThrowingTaskGroup(of: ([AgentStreamEvent], String).self) { group in
        group.addTask {
            var events: [AgentStreamEvent] = []
            var text = ""
            for try await e in stream {
                events.append(e)
                if case .textDelta(let d) = e { text += d }
                if case .toolInputDelta(let name, _) = e { print("    [stream] tool input delta: \(name)") }
            }
            return (events, text)
        }
        group.addTask {
            try await Task.sleep(nanoseconds: 150_000_000_000)
            throw NSError(domain: "validator", code: 1, userInfo: [NSLocalizedDescriptionKey: "stream timed out after 150s"])
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

do {
    print("== LIVE gateway: \(baseURL.absoluteString) agent=\(agentID) session=\(session.externalSessionKey) ==")

    print("-- Turn 1: 'Where am I?' with the canonical minis_* tool set --")
    let (t1, t1Text) = try await collect(
        messages: [AgentMessage(role: .user, parts: [.text("Where am I? Answer in one short sentence. If you need my location, use the minis_shell_execute tool with the command `apple-location`.")])],
        tools: realTools(),
        maxTokens: 4096
    )
    if !t1Text.isEmpty { print("    [text] \(t1Text)") }
    let completes = t1.compactMap { e -> (String, String, [String: Any])? in
        if case .toolCallComplete(let id, let name, let args, _) = e { return (id, name, args) }
        return nil
    }
    if case .done(let reason)? = t1.last { print("    [done] \(reason)") }
    expect(!completes.isEmpty, "agent issued a tool call in turn 1")
    guard let call = completes.first else {
        print("No tool call; turn 1 ended with text only. Live probe aborted (no phone-side tool to simulate).")
        print(failures.isEmpty ? "LIVE PROBE COMPLETE" : "\(failures.count) FAILED")
        exit(failures.isEmpty ? 0 : 1)
    }
    expect(call.1 == "shell_execute", "tool call decoded to shell_execute (got \(call.1))")
    let cmd = call.2["command"] as? String ?? ""
    print("    [tool] id=\(call.0) name=\(call.1) command=\(cmd)")

    let locationJSON = "{\"ok\":true,\"lat\":31.2304,\"lng\":121.4737,\"accuracy\":10,\"timestamp\":\"2026-08-10T00:00:00Z\",\"status\":\"simulated-on-phone\"}"
    print("-- Turn 2: simulate phone-side offload result, same session --")
    let (t2, t2Text) = try await collect(
        messages: [
            AgentMessage(role: .assistant, parts: [.toolUse(id: call.0, name: call.1, input: call.2)]),
            AgentMessage(role: .user, parts: [.toolResult(id: call.0, name: call.1, content: locationJSON, isError: false)]),
        ],
        tools: realTools(),
        maxTokens: 4096
    )
    print("    [final] \(t2Text)")
    expect(!t2Text.isEmpty, "agent produced a final answer after the tool result")
    if case .done(let reason)? = t2.last { print("    [done] \(reason)") }

    print(failures.isEmpty ? "\nLIVE PROBE PASSED (real gateway roundtrip OK)" : "\n\(failures.count) LIVE CHECK(S) FAILED")
    exit(failures.isEmpty ? 0 : 1)
} catch {
    print("LIVE PROBE ERROR: \(error)")
    exit(2)
}
