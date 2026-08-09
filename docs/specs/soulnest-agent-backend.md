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

OpenMinis exposes one external backend provider surface and keeps transport/session details inside backend-specific adapters.

Conceptual shape:

```text
OpenMinis Agent Loop
        |
External Agent Backend Provider
        |
        +-- OpenClawBackend
        +-- HermesBackend
```

The shared provider receives the current OpenMinis chat session identity in addition to the normal provider inputs.

Conceptual interface:

```swift
protocol ExternalAgentBackend {
    func stream(
        request: AgentBackendRequest
    ) async throws -> AsyncThrowingStream<AgentStreamEvent, Error>
}
```

The concrete request carries the canonical OpenMinis session identity, messages, tools and normal stream settings. Existing raw-LLM providers keep their existing contract; only the external backend bridge is session-aware.

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

The canonical external key is derived from the OpenMinis session ID:

```text
soulnest:<openminis-session-id>
```

Adapters may transform that value only when required by the backend contract.

## OpenClaw adapter

OpenClaw is an agent backend, not a raw LLM provider.

The current OpenClaw adapter uses the Gateway OpenAI-compatible `/v1/chat/completions` surface and is responsible for:

- selecting the intended OpenClaw agent, initially Yujie
- mapping the OpenMinis session ID to a stable OpenClaw session
- preserving OpenAI-compatible client function-tool calls so OpenMinis can execute its existing tools
- streaming text/tool events back as normal `AgentStreamEvent` values
- keeping OpenClaw-specific authentication and transport logic out of generic OpenMinis providers
- sending only the current-turn delta into the persistent OpenClaw session rather than replaying accumulated OpenMinis history

For OpenClaw, the stable `soulnest:<openminis-session-id>` value is sent as the request `user` identity. Because OpenClaw persists the resulting agent session, later requests must not resend old OpenMinis turns. A normal turn sends the latest user turn; a client-tool follow-up sends the relevant assistant tool call plus matching `role: "tool"` result(s).

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

OpenMinis remains the executor for tools that originate from the OpenMinis tool set.

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

### OpenClaw wire naming

For the OpenClaw path, ownership is deterministic on the wire:

```text
minis_*          -> caller-supplied OpenMinis/iPhone tool; execute in OpenMinis
other tool names -> OpenClaw-native/server-side tools; execute in OpenClaw
```

Only caller-supplied OpenMinis tools are namespaced. The adapter applies a reversible generic `minis_` prefix before sending tool definitions or replaying assistant client-tool calls, and strips one prefix from returned client tool calls before handing them to the existing OpenMinis handler.

Examples:

```text
location       -> minis_location
calendar_list  -> minis_calendar_list
photos_search  -> minis_photos_search
```

Do not rename OpenClaw-native/internal tools. OpenClaw already distinguishes its internal tools from caller-supplied client tools; a SoulNest-specific OpenClaw plugin is not required merely to preserve this ownership boundary.

For overlapping domains such as Calendar, `minis_calendar_*` means the current iPhone/Apple Calendar tool surface. OpenClaw's existing calendar/cloud tools remain server-side capabilities.

Hermes may use a different backend-specific wire convention, but it must preserve the same ownership semantics without changing the OpenMinis-facing tool runtime.

## System prompt policy

Prompting may reinforce tool ownership, but correctness must not rely only on prose when the transport can preserve deterministic ownership information.

For OpenClaw, do **not** forward the full OpenMinis raw-agent system prompt, persona, Skills/MCP prompt fragments, GLOBAL memory, or daily memory into Yujie. OpenClaw owns Yujie's identity, memory and context.

The OpenClaw adapter may send only a small fixed policy describing the device-tool boundary, for example that `minis_*` tools represent capabilities/data on the current iPhone and should be awaited after invocation.

This prevents SoulNest from creating a second competing persona/memory layer inside OpenMinis.

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

## Credential boundary

Backend transport credentials stay inside the backend adapter/configuration layer.

For OpenClaw, the Gateway bearer token is an owner/operator credential and must not be persisted in plaintext `UserDefaults`. Secure persistence belongs in Keychain-backed configuration (#4). Base URL and non-secret agent selection may use normal application configuration.

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
2. The external backend requests the namespaced client tool.
3. The adapter decodes the returned client-tool name.
4. OpenMinis executes the existing tool without a new SoulNest-native implementation.
5. The result returns through `role: "tool"` with the matching `tool_call_id` to the same backend session.
6. The backend produces the final response.

### Backend substitution

1. Configure OpenClaw backend and use OpenMinis normally.
2. Configure Hermes backend instead.
3. The OpenMinis tool runtime and Avatar implementation require no architectural rewrite.
4. Only backend-specific transport/session behavior changes.

## Non-goals

This contract does not add capabilities OpenMinis does not already have. In particular, it does not require background geofencing, a new device MCP server, a custom iPhone inbound server, a second memory system, a new agent loop, Live2D, 3D rendering or precise lip sync.
