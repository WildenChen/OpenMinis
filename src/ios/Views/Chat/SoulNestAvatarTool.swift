import Foundation

@MainActor
enum SoulNestAvatarTool {
    static func definition(for entry: ModelEntry?) -> AgentToolDefinition? {
        guard let entry,
              ProviderConfigStore.shared.instance(for: entry.providerInstanceId)?.providerType == .openClaw else {
            return nil
        }
        return AgentToolDefinition(
            name: "avatar_presentation",
            description: "Set the SoulNest Avatar's local presentation without adding control text to the conversation. Use a presentation state exposed by Avatar settings and an already-configured outfit ID. App lifecycle events may temporarily override playback.",
            parameters: [
                "emotion": AgentToolParam(type: .string, description: "Optional configured Avatar presentation state.", enumValues: NativeAvatarEmotion.allCases.map(\.rawValue)),
                "outfit": AgentToolParam(type: .string, description: "Optional existing SoulNest outfit ID.", enumValues: NativeAvatarPreferences.shared.outfits),
            ],
            required: [],
            propertyOrdering: ["emotion", "outfit"]
        )
    }

    static func execute(toolArgs: [String: Any]) -> (output: String, success: Bool) {
        let emotion = toolArgs["emotion"] as? String
        let outfit = toolArgs["outfit"] as? String
        let output = SoulNestAvatarPresentation.agentPresentation(emotion: emotion, outfit: outfit)
        let success = !output.hasPrefix("Ignored")
        return (output, success)
    }
}
