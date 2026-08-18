# SoulNest Upstream OpenMinis Sync Strategy

## Goal

Keep SoulNest easy to update when `OpenMinis/OpenMinis` publishes a new source release. SoulNest-specific behavior should remain visibly additive, with only a small audited set of hooks in upstream-owned files.

No automated process may overwrite SoulNest `main` directly.

## Remotes

Recommended local layout:

```sh
git remote -v
# origin   -> https://github.com/WildenChen/OpenMinis.git
# upstream -> https://github.com/OpenMinis/OpenMinis.git
```

Add upstream once if needed:

```sh
git remote add upstream https://github.com/OpenMinis/OpenMinis.git
git fetch upstream --tags
```

## SoulNest-owned additive areas

These areas are expected to contain fork-specific implementation and should normally survive upstream updates without conflict:

```text
src/ios/Providers/AgentBackend/
src/ios/Resources/Avatar/
src/ios/WebApp/AvatarShellWebViewController.swift
src/ios/Views/Settings/AvatarSettingsView.swift
docs/specs/soulnest-*.md
docs/development/multi-agent-workflow.md
docs/development/upstream-sync.md
scripts/gen_avatar_placeholders.py
```

Future SoulNest features should prefer these or similarly dedicated areas rather than editing upstream provider/runtime implementations.

## Intentional upstream-owned touch points

As of the upstream v1.12 sync, the intentional integration hooks are:

- `src/ios/Agent/Chat/AIChatViewModel+ConcurrentTools.swift`
  - 2-line execution hook delegating `avatar_presentation` to `SoulNestAvatarTool.execute`
- `src/ios/Agent/Chat/AIChatViewModel+ProviderFactory.swift`
  - resolve/make the active external backend provider (.openClaw, .hermes) without special-casing existing raw-LLM providers
- `src/ios/Agent/Chat/AIChatViewModel+ToolDefinitions.swift`
  - 2-line registration hook delegating `avatar_presentation` tool schema to `SoulNestAvatarTool.definition`
- `src/ios/Agent/Chat/AIChatViewModel.swift`
  - model fallback metadata adjustments and System-TTS synthesizer delegate hook for Avatar lifecycle tracking
- `src/ios/Debug/DebugRPCProviderChat.swift`
  - credential and custom base support for first-class OpenClaw/Hermes providers in debug RPC
- `src/ios/MinisApp.swift`
  - AppGroup identifier and FileProvider domain identifier for SoulNest bundle identity
- `src/ios/Minis.xcodeproj/project.pbxproj`
  - register SoulNest source files/resources and target bundle identifiers / marketing version
- `src/ios/Providers/LLMProviderFactory.swift`
  - voiceOnlyProvider branch for .openClaw / .hermes
- `src/ios/Providers/ProviderConfigStore.swift`
  - legacy OpenClaw marker migration during provider config initialization
- `src/ios/Providers/Voice/VoiceProviderFactory.swift`
  - nil branch for .openClaw / .hermes
- `src/ios/Views/Chat/AIChatView.swift`
  - primary immersive Avatar shell fullScreenCover presentation and mic turn bridge
- `src/ios/Views/Chat/ChatInputBar.swift`
  - VideoFileTransferable original filename preservation for Avatar custom video import
- `src/ios/Views/ContentView.swift`
  - navigation link to AvatarSettingsView and launch-time ensureChatForPendingAvatar hook
- `src/ios/Views/Providers/AddProviderView.swift`
  - configuration section for OpenClaw Gateway / Hermes provider types
- `src/ios/Views/Providers/ProviderInstanceDetailView.swift`
  - agent target ID and non-synced Keychain credential handling for external backend instances

Treat edits outside this list as suspicious during upstream sync unless a later SoulNest Issue explicitly adds a new intentional hook. Update this document whenever the intentional touch-point list changes.

## Update procedure

Never merge a new upstream release straight into `main` without review.

1. Finish/park active coding-agent work and update local `main` from `origin`.
2. Fetch upstream tags/branches.
3. Create a dedicated sync branch from SoulNest `main`.
4. Compare the selected upstream release/commit with the currently integrated upstream base.
5. Merge or rebase the selected upstream release into the sync branch.
6. Resolve conflicts with priority on preserving upstream behavior plus the smallest SoulNest hook.
7. Audit every changed upstream-owned file against the touch-point list above.
8. Run targeted validation based on the areas changed.
9. Open a PR from the sync branch into SoulNest `main`.
10. Squash/merge only after review and any required device/native validation.

Example shape:

```sh
git fetch origin
git fetch upstream --tags
git switch main
git pull --ff-only origin main
git switch -c sync/openminis-<release>

# Choose one reviewed integration method; do not blindly force-update main.
git merge <upstream-release-or-commit>
```

Whether merge or rebase is used is less important than keeping the sync isolated in a reviewable branch and preserving the SoulNest patch surface.

## Conflict policy

When upstream changes one of the intentional touch points:

1. Understand the new upstream behavior first.
2. Reapply the SoulNest behavior as the smallest compatible hook.
3. Do not restore large stale chunks merely because they existed in the fork.
4. Prefer moving SoulNest logic back into dedicated files if upstream now offers a cleaner extension point.
5. Do not fork or modify iSH/PRoot unless a concrete SoulNest requirement proves it necessary.

Existing upstream provider implementations such as `OpenAIProvider` should remain upstream-owned. OpenClaw/Hermes behavior belongs behind `Providers/AgentBackend/`.

## PR audit checklist

For every major SoulNest PR and every upstream sync PR, check:

- [ ] Is each upstream-owned file edit necessary?
- [ ] Could the logic be additive in a SoulNest-owned directory instead?
- [ ] Did the PR modify an existing raw-LLM provider for OpenClaw/Hermes behavior? If yes, redesign unless unavoidable.
- [ ] Did it duplicate an OpenMinis device capability instead of reusing the existing tool/offload?
- [ ] Did it add a new intentional upstream touch point? If yes, document it here.
- [ ] Are submodules still pointing at intended upstream/fork commits with no accidental local changes?
- [ ] Are secrets/customization/signing files excluded?
- [ ] Does the PR list focused validation and explicitly deferred device checks?

## Validation after an upstream sync

Use risk-based validation rather than automatically rebuilding everything.

At minimum, inspect/validate the areas touched by the upstream delta. If backend/chat-loop files changed, follow `AGENTS.md` validation order:

1. external backend returns a real response
2. same chat preserves session
3. different chat gets a different session
4. returning to the original chat resumes it
5. phone-side tool roundtrip
6. Avatar integration

If project/build files, native dependencies, signing, or device APIs changed upstream, perform the relevant native build/device validation before merging.

## Upstream base record

When completing a sync, record the upstream release/tag/commit in the sync PR description. Do not rely on memory to determine the next diff base.

Current integrated upstream base is commit `09fc199928de0f26685e766c34e6d541c7a69e5a` (tag `1.12`, PR #243). Earlier base was `9cf3a855fecd27bb5735b84cacbd56852a3ab8dd`.
