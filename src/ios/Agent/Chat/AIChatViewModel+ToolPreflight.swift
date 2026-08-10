import Foundation

// MARK: - Tool Preflight + JSON Repair

/// Thin app-side facade over `AgentToolPreflight`, which holds the pure logic
/// so the unit-test target can compile it without `AIChatViewModel`.
extension AIChatViewModel {

    // MARK: - Tool Preflight Validation

    /// Reject tool calls that have empty args or are missing required fields
    /// BEFORE the tool helper runs. Returns nil when the call is well-formed,
    /// or a human-readable reason string when it should be blocked.
    nonisolated static func preflightValidateToolCall(name: String,
                                                      args: [String: Any],
                                                      tools: [AgentToolDefinition]) -> String? {
        AgentToolPreflight.validateToolCall(name: name, args: args, tools: tools)
    }

    /// Fields that stay in each tool's `required` list (so the schema keeps
    /// nudging the model to always emit them) but must NOT block the call when
    /// absent. See `AgentToolPreflight.preflightNonBlockingFields`.
    nonisolated static var preflightNonBlockingFields: Set<String> {
        AgentToolPreflight.preflightNonBlockingFields
    }

    /// (tool name → field names) where an EMPTY STRING is a semantically valid
    /// value and must not be treated as "missing". See
    /// `AgentToolPreflight.preflightEmptyStringAllowedFields`.
    nonisolated static var preflightEmptyStringAllowedFields: [String: Set<String>] {
        AgentToolPreflight.preflightEmptyStringAllowedFields
    }

    nonisolated static func preflightEmptyStringAllowed(tool: String, field: String) -> Bool {
        AgentToolPreflight.preflightEmptyStringAllowed(tool: tool, field: field)
    }

    // MARK: - JSON Repair (T-tool-json-repair b2c4f8a6)

    /// Outcome of running the JSON-repair strategies on a tool call's args.
    struct ToolArgsRepairOutcome {
        let args: [String: Any]
        let repairs: [String]
    }

    /// Attempt to salvage a malformed / incomplete tool call's args BEFORE
    /// the preflight validator rejects it. See
    /// `AgentToolPreflight.repairToolArgs`.
    static func repairToolArgs(
        name: String,
        args: [String: Any],
        rawTail: String?,
        tools: [AgentToolDefinition]
    ) -> ToolArgsRepairOutcome {
        let outcome = AgentToolPreflight.repairToolArgs(name: name, args: args, rawTail: rawTail, tools: tools)
        return ToolArgsRepairOutcome(args: outcome.args, repairs: outcome.repairs)
    }

}
