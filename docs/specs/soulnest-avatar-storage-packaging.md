# SoulNest Avatar Storage & Packaging Strategy

## Goal

Keep SoulNest source clones small and easy to review while allowing final Yujie video packs to be replaced, versioned, and kept private without runtime code changes.

## Decision for MVP

Use a **manifest-first, bundled-default** design.

- Keep manifests, schemas, documentation, and tiny placeholder/emergency assets in normal Git.
- Do **not** put full generated Yujie HEVC/MP4 outfit packs in normal Git history.
- Do **not** add Git LFS for MVP. It adds repository/account workflow overhead before there is a proven need.
- The personal/private SoulNest build may source final video packs from a local/private asset directory at build/package time.
- If later public/distributed builds need downloadable packs, use versioned release assets or another external artifact host while preserving the same manifest contract.
- No downloader, ZIP installer, CDN client, marketplace, or automatic updater is required for MVP.

This keeps the source repository practical while leaving distribution policy reversible later.

## Source-control policy

### Keep in Git

- `manifest.json` and manifest examples
- JSON schema/specification
- Avatar HTML/CSS/JS runtime
- small placeholder or emergency fallback clips needed for development/first-frame safety
- scripts that are small and demonstrably needed for validation/build packaging
- documentation and reproducibility notes

### Keep out of normal Git history

- full generated Yujie master videos
- final multi-outfit HEVC/MP4 packs
- intermediate renders/source frames
- model checkpoints/LoRAs used to generate the assets
- private-use outfit packs

Large/private assets must be reproducible or identifiable by manifest version, but their binaries do not need to live in this repository.

## Canonical layout

The runtime resolves assets from a manifest rather than hardcoded filenames.

```text
AvatarAssets/
└── <assetVersion>/
    └── <outfit>/
        ├── idle_01.mp4
        ├── thinking.mp4
        ├── talk_soft.mp4
        └── ...
```

The manifest remains the source of truth for state → clip mapping and must expose an identifiable `assetVersion`.

For the current Yujie set, the canonical state/outfit contract is defined by `docs/specs/soulnest-avatar-video-assets.md`.

## Runtime lookup order

Use one deterministic lookup order:

1. Optional installed/private external pack matching the requested manifest/version.
2. Bundled app assets for the requested outfit/state.
3. Same-outfit fallback defined by the canonical Avatar manifest/spec.
4. Bundled emergency/default idle fallback.

Missing optional/private assets must never crash the Avatar shell. They fall back to bundled/default assets.

## Bundled assets

The iOS app bundle should contain the minimum assets required for a usable first launch and a safe fallback.

Example:

```text
Resources/Avatar/yujie/
├── manifest.json
└── casual/
    ├── idle_01.mp4
    ├── thinking.mp4
    ├── talk_soft.mp4
    └── caring.mp4
```

Final packaging may copy selected private/versioned assets into the app bundle during a local release build; the source repository does not need to contain those binaries.

## Optional external/private packs

Future or private outfit/video collections may live outside the app bundle, for example under an Application Support/private package location. They must use the same manifest schema as bundled assets.

MVP behavior is intentionally simple:

- no network download is required
- no background update daemon is required
- no custom ZIP installer is required
- the pack is either present and valid, or the runtime falls back to bundled assets

If downloadable packs are introduced later, package them as immutable versioned artifacts and install them atomically into a versioned directory. Partial downloads must never replace the last valid pack.

## Versioning and debugging

Every pack must expose a stable asset version in its manifest. Logs/debug UI should be able to identify at least:

- asset version
- selected outfit
- requested state
- resolved file/fallback state

Changing final videos without changing runtime code is expected; changing the manifest contract requires an explicit spec/runtime change.

## Repository-size guardrail

Before adding a video binary to normal Git, ask whether it is required for source review or basic fallback. If not, keep it external/private.

As a rule, generated production video packs belong outside normal Git history. A small emergency/demo clip is acceptable only when it materially improves first-run or test reliability.

## PWA compatibility

The standalone Avatar PWA should consume the same manifest/state/outfit contract. Its asset base URL may differ from the native app bundle path, but the presentation model must not fork.

PWA asset delivery does not replace native OpenMinis capabilities.

## Non-goals

- realtime generated Avatar assets
- Live2D/3D asset pipeline
- automatic CDN/update service
- asset marketplace/plugin system
- Git LFS migration for MVP
