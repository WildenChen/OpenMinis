# Contributing to this OpenMinis fork

This repository is the SoulNest development fork of OpenMinis.

- Fork: `WildenChen/OpenMinis`
- Upstream: `OpenMinis/OpenMinis`
- Default integration branch: `main`

The upstream repository is a published mirror and does not accept pull requests. This fork does accept pull requests for SoulNest development.

## Development model

Use focused branches and open pull requests into `main`.

Keep changes small and scoped. Prefer additive SoulNest files and narrow registration hooks over broad modifications to upstream OpenMinis code. Do not refactor unrelated code while implementing a feature.

The primary product goal is to preserve OpenMinis as the mobile/device runtime while adding:

1. a generic external Agent Backend provider,
2. OpenClaw and Hermes backend adapters,
3. stable OpenMinis-chat-to-backend-session mapping,
4. a Yujie/SoulNest avatar experience.

Existing OpenMinis device capabilities should be reused rather than reimplemented.

## Pull requests

Before opening or merging a PR:

- explain what changed and why,
- identify the affected platform and scope,
- confirm no unrelated upstream refactor was included,
- run the smallest relevant validation for the change,
- note any real-device or backend validation that remains.

This fork uses squash merge so `main` stays easy to compare with and update from upstream.

Do not merge unless the task or repository owner explicitly calls for merge after the required validation.

## iOS development

The current SoulNest work is iOS-first. Do not modify Android unless the task explicitly requires it.

Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/WildenChen/OpenMinis.git
```

For an existing clone:

```sh
git submodule update --init --recursive
```

Follow `BUILDING.md` for native dependency preparation and build instructions.

## Secrets and local configuration

Never commit API tokens, OpenClaw/Hermes credentials, Apple signing credentials, or local provider customization files. Use the existing `.example` customization templates and local ignored files.

## Upstream sync

When a new OpenMinis release is adopted, keep upstream code recognizable and resolve conflicts by preserving the smallest SoulNest-specific patch surface possible. Do not opportunistically rewrite upstream code during an update.

See `AGENTS.md` for the architecture and implementation rules used by coding agents in this fork.
