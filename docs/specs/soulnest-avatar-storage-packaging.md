# SoulNest Avatar Storage & Packaging Strategy

## MVP goal

Keep Avatar assets simple and replaceable. The runtime must load assets through the manifest without requiring code changes when final Yujie videos replace placeholders.

## Storage layers

### 1. Bundled default assets

The iOS app bundle contains the default Yujie Avatar assets required for first launch.

Example:

```
Resources/Avatar/yujie/
├── manifest.json
└── casual/
    ├── idle_01.mp4
    ├── thinking.mp4
    ├── talk_soft.mp4
    └── caring.mp4
```

### 2. Optional external asset packs

Future large outfit/video collections may be delivered separately. They must use the same manifest contract as bundled assets.

Runtime behavior:

1. Look for external/private asset pack.
2. If unavailable, fallback to bundled assets.
3. Never require runtime code changes for new outfits.

## Packaging rules

- Keep video assets independent from backend/provider code.
- Do not introduce a custom installer or download system for MVP.
- Do not require ZIP package management in the first release.
- Keep manifest as the only runtime contract.

## PWA compatibility

The same manifest structure should be usable by the standalone Avatar PWA surface.

The PWA shares presentation assets but does not replace OpenMinis native capabilities.

## Non-goals

- Realtime generated Avatar assets.
- Live2D/3D asset pipeline.
- Complex CDN/update service.
- Asset marketplace or plugin system.
