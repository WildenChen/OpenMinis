# SoulNest Development Guidance

This fork extends OpenMinis into the mobile body for SoulNest while keeping upstream OpenMinis easy to update.

## Project intent

- OpenMinis remains the native mobile runtime and device-capability layer.
- SoulNest adds an external Agent Backend abstraction and a Yujie avatar experience.
- The external backend is the real agent brain. Initial adapters are OpenClaw and Hermes.
- Reuse OpenMinis capabilities as-is. Do not rebuild device integrations that OpenMinis already provides.

## Current priority

1. iOS first. Do not change Android unless the task explicitly requires it.
2. Add a generic external Agent Backend provider with small registration changes only.
3. Add OpenClaw and Hermes adapters behind the same backend abstraction.
4. Preserve one-to-one conversation continuity: one OpenMinis chat session maps to one backend agent session; returning to the chat resumes that same backend session.
5. Allow the backend agent to use the existing OpenMinis tool loop and native offloads.
6. Add the SoulNest/Yujie avatar after the backend/session/tool roundtrip is proven.

## Architecture boundaries

- Keep existing OpenMinis providers, agent loop, native offloads, skills, MCP, Linux sandbox, browser, storage, and device integrations intact unless a narrowly required compatibility hook is unavoidable.
- Prefer additive files under a dedicated provider/backend area over edits to existing provider implementations.
- Do not add OpenClaw-specific behavior to `OpenAIProvider` or other existing providers.
- Do not change the global `AgentProvider` protocol merely to support backend sessions if a narrower session-aware extension/protocol can solve it.
- Keep OpenClaw and Hermes backend-specific transport/session behavior inside their adapters.
- Do not duplicate Location, Calendar, Reminders, Contacts, Photos, Speech, HealthKit, HomeKit, Bluetooth, Notifications, or other existing OpenMinis capabilities.
- OpenMinis capabilities that do not currently exist are out of scope unless explicitly requested.

## External Agent Backend target shape

Prefer a structure equivalent to:

```text
Providers/AgentBackend/
├── AgentBackendProvider.swift
├── AgentBackendProtocol.swift
├── AgentBackendConfig.swift
├── OpenClawBackend.swift
└── HermesBackend.swift
```

The exact names may change if the existing project conventions strongly suggest better names, but keep the responsibilities separated.

### OpenClaw

- Route to the selected OpenClaw agent, initially Yujie.
- Preserve backend session continuity using the OpenMinis session identifier.
- Keep OpenMinis device-tool execution on the phone; keep OpenClaw host/tool execution on OpenClaw.
- Avoid inventing a private protocol when an existing OpenClaw HTTP/Gateway contract is sufficient.

### Hermes

- Use the same OpenMinis-facing backend abstraction as OpenClaw.
- Preserve OpenMinis-session-to-Hermes-session continuity using Hermes' supported session/conversation APIs.
- Do not fork the SoulNest UI or device-tool layer for Hermes.

## Tool ownership

The external agent may see both phone-side and backend-side capabilities. Keep their ownership unambiguous.

- Phone/device capabilities are executed by OpenMinis.
- Backend/host capabilities are executed by OpenClaw or Hermes.
- Prefer explicit tool naming/metadata over relying only on prompt wording when a small compatibility layer can make ownership deterministic.

## Avatar scope

The first avatar implementation should be simple and independent of the agent backend.

- Photorealistic Yujie presentation.
- Prefer pre-generated local video states such as idle, thinking, talking, happy, shy, sad, angry, and excited.
- Subtitle-style response display rather than a conventional chat-bubble-first UI.
- Support outfit asset sets.
- Exact lip sync, Live2D, 3D, Duix, and realtime neural avatar generation are not MVP requirements.
- Reuse OpenMinis WebApp/WKWebView facilities where practical before adding native UI infrastructure.

## Development rules

- Inspect the existing implementation before designing a new abstraction.
- Make the smallest change that satisfies the requested behavior.
- Do not refactor unrelated upstream code.
- Do not add speculative frameworks, architecture layers, CI systems, caches, sync engines, or generalized infrastructure without a concrete requirement.
- Do not turn an implementation request into a test-only or documentation-only task.
- Keep commits scoped and reversible.
- Preserve upstream behavior unless the change is explicitly part of SoulNest.
- Never commit secrets, API tokens, signing credentials, or local customization files.

## Git workflow

- `main` is the integration branch for this fork.
- Work on focused feature/fix branches and open PRs into `main`.
- Repository merge policy is squash merge.
- Do not merge a PR unless the user explicitly requested merge or the task explicitly includes validated merge.
- Keep upstream-origin changes easy to distinguish from SoulNest changes.
- When syncing upstream, prefer merging/rebasing the upstream release into the fork with SoulNest-specific changes kept as small additive patches.

## Build setup

Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/WildenChen/OpenMinis.git
```

For an existing clone:

```sh
git submodule update --init --recursive
```

Follow `BUILDING.md` for native dependencies. For iOS, the official first-build order is:

```sh
./deps/build_lame.sh
./deps/build_ffmpeg.sh
./deps/build_ish.sh
./deps/prepare_alpine_rootfs.sh
```

Then build `src/ios/Minis.xcodeproj` with the `Minis` scheme. Prefer a device/generic iOS build; do not spend time creating simulator-specific native dependencies unless the task requires simulator support.

## Validation order

For backend work, validate in this order:

1. OpenMinis can send a turn to the selected external backend and receive the real agent response.
2. A second turn in the same OpenMinis chat resumes the same backend session.
3. A new OpenMinis chat creates/uses a different backend session.
4. Returning to the original OpenMinis chat resumes its original backend session.
5. A phone-side tool call can round-trip through the backend agent, execute in OpenMinis, return its result, and produce the final backend-agent answer.
6. Only after those work, integrate avatar state and presentation.

Do not expand the test matrix beyond the affected feature unless a regression or explicit request requires it.
