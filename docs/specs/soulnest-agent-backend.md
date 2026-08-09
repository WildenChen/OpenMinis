# SoulNest External Agent Backend Contract

## Purpose

SoulNest keeps OpenMinis as the mobile runtime and device-capability layer while delegating the real agent brain to an external backend. Initial backends are OpenClaw and Hermes.

This contract exists so OpenMinis can support either backend without duplicating mobile capabilities or creating a second independent agent identity.

## Core responsibilities

### OpenMinis owns

- the native iOS app runtime
- the existing OpenMinis agent/tool loop
- existing Native Offloads and device integrations
- local UI, input, speech capture, attachments, browser, Linux sandbox, Skills and MCP client capabilities
- execution of tools that are exposed by OpenMinis to the backend model
- the canonical local chat/session identifier
- Avatar presentation only

OpenMinis capabilities must be reused as-is. SoulNest must not reimplement Location, Calendar, Reminders, Contacts, Photos, Speech, HealthKit, HomeKit, Bluetooth, Notifications, Browser, Linux or other existing OpenMinis capabilities.

### External backend owns

- the real agent identity and personality
- long-term memory and backend-side context
- reasoning and response generation
- backend-native tools and policies
- backend session persistence

The backend must not create a second mobile agent layer that competes with the OpenMinis tool loop.

## Shared backend abstraction

OpenMinis should expose one external backend provider surface and keep transport/session details inside backend-specific adapters.

Conceptual shape:

```text
OpenMinis Agent Loop
        |
External Agent Backend Provider
        |
        +-- OpenClawBackend
        +-- HermesBackend
```

The shared provider should receive the current OpenMinis chat session identity in addition to the normal provider inputs.

Conceptual interface:

```swift
protocol ExternalAgentBackend {
    func stream(
        sessionID: String,
        messages: [AgentMessage],
        systemPrompt: String?,
        tools: [AgentToolDefinition],
        maxTokens: Int,
        thinkingLevel: ThinkingLevel
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error>
}
```

Exact Swift naming may differ, but the behavior must match this contract.

## Session semantics

The OpenMinis chat session ID is the canonical client conversation identity.

Required behavior:

```text
OpenMinis chat A -> backend session A
OpenMinis chat B -> backend session B
return to chat A -> resume backend session A
new OpenMinis chat C -> create backend session C
```

Rules:

1. Two distinct OpenMinis chats must never silently share one backend session.
2. Reopening an existing OpenMinis chat must not create a fresh backend session.
3. Session mapping must be deterministic and not depend on the full message text.
4. Backend-specific session identifiers stay inside the adapter.
5. The provider must not require users to manually configure one session key per chat.
6. Backend session continuity must survive normal app navigation and reconnects.

A safe canonical external key is derived from the OpenMinis session ID, for example:

```text
soulnest:<openminis-session-id>
```

Adapters may transform that value to match backend requirements.

## OpenClaw adapter

OpenClaw should be treated as an agent backend, not as a raw LLM provider.

The adapter is responsible for:

- selecting the intended OpenClaw agent, initially Yujie
- mapping the OpenMinis session ID to a stable OpenClaw session
- preserving OpenAI-compatible function tool calls so OpenMinis can execute its existing tools
- streaming text/tool events back as normal `AgentStreamEvent` values
- keeping OpenClaw-specific authentication and transport logic out of generic OpenMinis providers

Where supported by the target OpenClaw version, session routing should use its stable session controls rather than reconstructing identity from chat history.

## Hermes adapter

Hermes should implement the same OpenMinis-facing contract.

The adapter is responsible for:

- selecting the intended Hermes profile/agent
- mapping the OpenMinis session ID to a stable Hermes conversation/session
- preserving supported streaming semantics
- converting Hermes API events into normal `AgentStreamEvent` values
- keeping Hermes-specific authentication and transport logic isolated in the adapter

The adapter may use Hermes conversation/session APIs rather than OpenAI Chat Completions when that provides stronger native continuity.

## Tool ownership and roundtrip

OpenMinis must remain the executor for tools that originate from the OpenMinis tool set.

Expected flow:

```text
user message
  -> OpenMinis Agent Loop
  -> external backend
  -> backend requests an OpenMinis tool
  -> OpenMinis executes existing tool/native offload
  -> tool result returns through the same backend session
  -> backend produces final response
```

The implementation must not proxy every OpenMinis capability through custom SoulNest REST endpoints.

Backend-native tools continue to execute in the backend runtime.

If tool names can collide, the adapter/provider layer must introduce a deterministic ownership rule. Prefer a minimal namespace or metadata mechanism over large prompt-only heuristics.

Conceptually:

```text
minis.*      -> execute in OpenMinis
openclaw.*   -> execute in OpenClaw
hermes.*     -> execute in Hermes
```

The exact wire names may differ if existing OpenMinis tool names must remain unchanged, but ownership must be unambiguous.

## System prompt policy

Prompting may reinforce tool ownership, but correctness must not rely only on prose instructions when the transport/provider can preserve deterministic ownership information.

The backend should be told that:

- it is the real SoulNest/Yujie agent brain
- OpenMinis is the mobile runtime and tool executor
- OpenMinis-provided tools represent capabilities of the current phone/app session
- existing backend-native tools remain available according to backend policy

## Avatar boundary

Avatar is presentation state, not a second agent.

The backend may optionally emit or derive presentation metadata such as:

```json
{
  "state": "talking",
  "emotion": "happy",
  "outfit": "casual"
}
```

Avatar state must not change session identity, tool routing or memory semantics.

Avatar implementation should remain separable from the backend provider so OpenClaw and Hermes can share the same visual body.

## Failure and reconnect behavior

- A transient network failure must not cause a new backend session to be created for an existing OpenMinis chat.
- Retrying the same chat must reuse its mapped backend session.
- Authentication failures should be surfaced as provider/backend errors and must not fall back silently to a different agent backend.
- Switching the configured backend is explicit. The implementation must not silently reinterpret an OpenClaw session as a Hermes session or vice versa.
- Backend-specific state required for continuation may be persisted only when necessary; prefer deterministic mapping from the OpenMinis session ID when the backend supports it.

## Compatibility constraints

- Existing OpenMinis providers must continue to behave unchanged.
- Do not add OpenClaw-specific or Hermes-specific behavior to `OpenAIProvider`.
- Avoid changing the global `AgentProvider` contract if a narrower session-aware/external-backend protocol is sufficient.
- Prefer new files plus small registration points.
- iOS is the first implementation target. Android is out of scope unless explicitly requested.

## Acceptance examples

### Session continuity

1. Create OpenMinis chat A.
2. Send two messages.
3. Create chat B and send one message.
4. Return to chat A.
5. The backend continues chat A with its original backend session and memory.

### Tool roundtrip

1. Ask a question that requires an existing OpenMinis device tool.
2. The external backend requests that tool.
3. OpenMinis executes the existing tool without a new SoulNest-native implementation.
4. The result returns to the same backend session.
5. The backend produces the final response.

### Backend substitution

1. Configure OpenClaw backend and use OpenMinis normally.
2. Configure Hermes backend instead.
3. The OpenMinis tool runtime and Avatar implementation require no architectural rewrite.
4. Only backend-specific transport/session behavior changes.

## Non-goals

This contract does not add capabilities OpenMinis does not already have. In particular, it does not require background geofencing, a new device MCP server, a custom iPhone inbound server, a second memory system, a new agent loop, Live2D, 3D rendering or precise lip sync.