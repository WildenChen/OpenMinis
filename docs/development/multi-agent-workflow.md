# SoulNest Multi-Agent Development Workflow

## Problem

Codex, OpenCode and other coding agents may share the same local checkout. Multiple agents modifying the same working tree can overwrite changes or create invalid branches.

## Rules

- One coding agent owns one active working tree.
- Do not run multiple coding agents concurrently in the same checkout.
- Use separate git worktrees when parallel coding is required.
- Shared core files require a single owner.

## Ownership

Shared areas:

- External Agent Backend foundation
- Provider registration
- Session routing
- Tool forwarding contracts

Only one agent should modify these areas at a time.

Independent areas may proceed separately:

- Avatar web assets
- Documentation
- Video production assets

## Merge order

1. Shared contracts and interfaces.
2. Backend adapters.
3. Tool ownership and roundtrip integration.
4. Presentation integration.
5. End-to-end validation.

## Agent handoff

Before starting a new agent task:

- Confirm current main branch is updated.
- Confirm no other agent owns the same files.
- State exact issue scope and non-goals.
- Avoid unrelated refactoring.
