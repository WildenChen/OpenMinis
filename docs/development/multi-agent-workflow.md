# SoulNest Multi-Agent Development Workflow

## Purpose

Keep Codex, OpenCode, Antigravity, ChatGPT/GitHub work, and manual development from overwriting one another or repeatedly rediscovering project setup.

The default rule is simple: **one coding agent per working tree**.

## Required reading before architecture changes

Every coding agent must read:

1. `AGENTS.md`
2. `docs/specs/soulnest-agent-backend.md`
3. The target GitHub Issue and its latest comments
4. Any directly related spec named by the Issue

Do not redesign shared architecture from memory when these files already define it.

## Fresh clone / setup

Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/WildenChen/OpenMinis.git
cd OpenMinis
```

For an existing clone:

```sh
git submodule update --init --recursive
```

For iOS build-time customization:

```sh
cp src/ios/Configs/ProviderCustomization.xcconfig.example \
   src/ios/Configs/ProviderCustomization.xcconfig
```

Empty customization values are valid for a normal build unless the specific feature requires one.

For a first native iOS build, follow `BUILDING.md`. The required dependency order is:

```sh
./deps/build_lame.sh
./deps/build_ffmpeg.sh
./deps/build_ish.sh
./deps/prepare_alpine_rootfs.sh
```

These steps can take roughly 30–60 minutes on the first build. Do not run them for documentation-only or standalone WebApp-only changes unless native validation is actually required.

## Working-tree ownership

- One coding agent owns one active working tree.
- Do not run multiple coding agents concurrently in the same checkout.
- `git checkout`, `git switch`, rebases, generated files, and dependency scripts all affect the shared working tree even when agents intend to use different branches.
- If parallel coding is required, each agent must use a separate `git worktree` directory.

Example:

```sh
git fetch origin
git worktree add ../OpenMinis-opencode -b opencode/11-avatar-webapp-shell origin/main
git worktree add ../OpenMinis-codex -b codex/8-tool-ownership origin/main
```

Do not create parallel worktrees when sequential execution is fast enough; fewer moving parts is preferable.

## Branch / PR rules

- `main` is integration only.
- One Issue per focused branch/PR unless two Issues are intentionally inseparable and the PR states why.
- Suggested branch form: `<agent-or-owner>/<issue>-<short-topic>`.
- Rebase or update from current `origin/main` before opening/finalizing the PR.
- Use squash merge.
- PR body must reference the Issue, list validation performed, and list deferred real-device/native checks explicitly.
- Never commit secrets, tokens, signing credentials, or local customization files.

## Shared-core ownership

Only one active coding task may modify shared integration areas at a time, including:

- `src/ios/Providers/AgentBackend/`
- external backend registration/factory wiring
- session-aware provider routing
- OpenMinis tool forwarding/ownership mapping
- central chat-loop hooks
- `src/ios/Minis.xcodeproj/project.pbxproj` when the same files/groups are being registered

When a shared-core PR is in progress, other tasks should stay in clearly independent areas such as documentation, isolated Avatar web assets, or offline video production.

## Independent work that can usually proceed in parallel

Provided separate worktrees are used when coding simultaneously:

- Avatar HTML/CSS/JS that does not touch backend integration
- documentation/specification
- offline video production assets
- isolated test fixtures that do not change shared registration

“Different branch” does **not** by itself mean “safe to run concurrently” when agents share the same checkout.

## Validation policy

Use the smallest validation that proves the changed scope.

- Docs-only: inspect links/paths/spec consistency; no native build.
- WebApp-only: run the standalone HTML/JS/state/asset checks; native build may be deferred.
- Backend pure-wire logic: focused harness/unit tests first.
- Shared native integration: targeted Xcode build/test when dependencies are already available or when the Issue acceptance requires it.
- Real OpenClaw/device-tool behavior: validate against the real Gateway/device at the dedicated integration/E2E stage.

Do not spend 30–60 minutes rebuilding native dependencies merely to validate a documentation or isolated web change.

## Merge order

Prefer this integration order when dependencies overlap:

1. Shared contracts/interfaces.
2. Backend adapters/session mapping.
3. Tool ownership/catalog/roundtrip integration.
4. Presentation integration.
5. End-to-end validation and packaging.

A dependent branch should rebase onto the merged dependency before final review.

## Handoff template

Every coding agent should finish with a concise handoff:

```text
Issue: #<number> <title>
Branch: <branch>
Commit(s): <sha or summary>
Changed files:
- ...

Validation performed:
- ...

Deferred / not validated:
- native build
- real Gateway roundtrip
- on-device acceptance

PR: <number/url if created>
```

If there is an unresolved design decision, state it explicitly rather than silently choosing a broader architecture.

## Before starting the next agent

1. Finish or stop the current coding agent.
2. Commit/push its work.
3. Review/merge or deliberately park its branch.
4. Return the local checkout to `main`.
5. `git pull --ff-only` (or otherwise update to current `origin/main`).
6. Confirm the next Issue does not collide with another active worktree/branch owner.
7. Start the next agent with one clear goal and explicit non-goals.

## Current SoulNest architecture boundary

OpenMinis remains the iPhone runtime/tool executor. OpenClaw/Hermes are external agent brains. Existing OpenMinis providers and native capabilities should not be refactored merely to support SoulNest.

For backend work, the canonical follow-on validation order remains the one in `AGENTS.md`: backend response → same-chat continuity → different chat → return to original → phone-tool roundtrip → Avatar integration.
