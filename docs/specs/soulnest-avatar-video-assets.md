# SoulNest Avatar Video Asset Specification

## Purpose

This document defines the first production contract for SoulNest/Yujie avatar video assets.

The Avatar is a presentation layer only. It does not own agent identity, memory, session routing, or tools. OpenMinis remains the iPhone runtime, while OpenClaw or Hermes remains the agent backend.

The MVP intentionally uses pre-generated local video clips. Live2D, 3D, Duix, exact lip sync, and realtime neural avatar generation are out of scope.

## Canonical delivery format

Use one canonical portrait master for all MVP clips:

- Canvas: `1080 x 1920` portrait (9:16).
- Frame rate: `30 fps`.
- Video codec: HEVC/H.265 when bundled in the iOS app or local asset pack.
- Container: `.mp4` or `.mov`; prefer `.mp4` unless the chosen encoder/toolchain produces a more reliable `.mov` HEVC output.
- Audio: omit audio from avatar clips. Speech/TTS is a separate playback layer.
- Color: SDR Rec.709 unless a later asset pipeline explicitly standardizes HDR end-to-end.
- Pixel aspect ratio: square pixels.
- Orientation metadata: export physically upright portrait frames; do not rely on rotation metadata.

A lower-resolution derivative may be generated later for PWA/network delivery, but the 1080x1920 asset remains the canonical MVP source contract.

## Framing and visual continuity

All clips in an outfit set must look like the same continuous camera setup.

Required consistency:

- Same camera position, focal length/look, crop, and horizon.
- Same character scale and approximate eye position.
- Same background composition.
- Same lighting direction, exposure, white balance, and color grade.
- Same hair, face, body proportions, accessories, and outfit within one outfit set.
- Avoid camera moves, zooms, large body turns, sudden background motion, or major pose jumps.

Recommended framing:

- Character centered or slightly above center.
- Head and torso visible, with enough lower-body framing that outfit differences remain visible on an iPhone portrait screen.
- Keep subtitle-safe space near the lower-middle area and UI-safe space at the very bottom for text/microphone controls.
- Avoid placing important facial detail under the Dynamic Island/status area.

## Identity requirements

Yujie identity should be generated from the project's existing approved reference images/LoRA/source assets. The exact generation tool is not part of the runtime contract.

Each final clip should preserve:

- face identity
- hairstyle and hair color
- age appearance
- body proportions
- skin tone and overall rendering style
- outfit identity for the selected wardrobe set

When a generated clip drifts visibly in face or body identity, regenerate it rather than compensating in runtime code.

## State catalog

The initial state names are fixed so the WebApp can use a manifest instead of hardcoded per-file logic.

Required base states:

| State | Intent | Playback type | Target duration |
|---|---|---|---|
| `idle_01` | default resting state | seamless loop | 4-8 s |
| `idle_02` | alternate resting state | seamless loop | 4-8 s |
| `thinking` | waiting/processing | seamless loop | 3-6 s |
| `talk_soft` | neutral/caring speech | seamless loop | 3-6 s |
| `talk_happy` | positive speech | seamless loop | 3-6 s |
| `talk_excited` | energetic speech | seamless loop | 3-6 s |
| `shy` | shy/embarrassed reaction | one-shot, then fallback | 2-5 s |
| `sad` | sad reaction | one-shot or gentle loop | 3-6 s |
| `angry` | angry/frustrated reaction | one-shot or gentle loop | 2-5 s |
| `caring` | caring/neutral reaction | one-shot or gentle loop | 3-6 s |

Optional future states may be added to the manifest without changing the runtime contract.

## Motion guidance

### Idle

Use subtle continuous movement only:

- natural blinking
- breathing
- small eye movement
- slight head/shoulder micro-movement

The first and last frames should be visually close enough that loop repetition is not obvious during normal viewing.

### Thinking

Thinking should remain calm and reusable for variable backend latency. Use small gaze/pose changes rather than a large one-time gesture.

### Talking

Talking clips are generic speaking motion only. Exact phoneme/lip synchronization is not required for MVP.

Talking clips should:

- keep mouth motion natural and continuous
- avoid exaggerated repeated gestures that expose the loop quickly
- preserve enough facial expression to distinguish soft/happy/excited variants
- remain usable with independent TTS audio

### Emotion/reaction clips

Short reaction clips may be one-shot. At completion, the Avatar controller should fall back to an appropriate loop state rather than requiring transition videos for MVP.

Recommended fallback:

- `shy` -> `idle_01`
- `sad` -> `idle_01`
- `angry` -> `idle_01`
- `caring` -> `idle_01`

If speech begins while an emotion is active, the controller may select the closest available talking variant.

## Outfit sets

Initial outfit IDs:

- `casual`
- `office`
- `pajamas`
- `shorts_private_casual`

`shorts_private_casual` may be kept in a local/private asset pack and is not required to live in the public repository.

Each final outfit set should provide at minimum:

- `idle_01`
- `thinking`
- `talk_soft`

For the primary/default outfit, provide the complete state catalog first. Secondary outfit sets may omit optional emotion clips and rely on manifest fallback behavior.

## Directory and naming convention

Logical asset layout:

```text
AvatarAssets/
└── yujie/
    ├── manifest.json
    ├── casual/
    │   ├── idle_01.mp4
    │   ├── idle_02.mp4
    │   ├── thinking.mp4
    │   ├── talk_soft.mp4
    │   ├── talk_happy.mp4
    │   ├── talk_excited.mp4
    │   ├── shy.mp4
    │   ├── sad.mp4
    │   ├── angry.mp4
    │   └── caring.mp4
    ├── office/
    ├── pajamas/
    └── shorts_private_casual/
```

Use lowercase ASCII file names with `_` separators. Do not encode backend names, session IDs, model names, or generation-tool names into runtime filenames.

## Manifest contract

Runtime code should resolve avatar assets through a manifest. Do not hardcode every filename in Swift or JavaScript.

Minimal shape:

```json
{
  "schemaVersion": 1,
  "character": "yujie",
  "assetVersion": "1",
  "defaultOutfit": "casual",
  "outfits": {
    "casual": {
      "defaultIdle": "idle_01",
      "fallbackTalking": "talk_soft",
      "states": {
        "idle_01": { "src": "casual/idle_01.mp4", "mode": "loop" },
        "idle_02": { "src": "casual/idle_02.mp4", "mode": "loop" },
        "thinking": { "src": "casual/thinking.mp4", "mode": "loop" },
        "talk_soft": { "src": "casual/talk_soft.mp4", "mode": "loop" },
        "talk_happy": { "src": "casual/talk_happy.mp4", "mode": "loop" },
        "talk_excited": { "src": "casual/talk_excited.mp4", "mode": "loop" },
        "shy": { "src": "casual/shy.mp4", "mode": "once", "fallback": "idle_01" },
        "sad": { "src": "casual/sad.mp4", "mode": "once", "fallback": "idle_01" },
        "angry": { "src": "casual/angry.mp4", "mode": "once", "fallback": "idle_01" },
        "caring": { "src": "casual/caring.mp4", "mode": "once", "fallback": "idle_01" }
      }
    }
  }
}
```

The final #11/#15 implementation may add fields when required, but should preserve the same basic state/outfit lookup model.

## Fallback behavior

Missing optional assets must not break the Avatar.

Resolution order:

1. requested state in selected outfit
2. selected outfit's `fallbackTalking` when the requested state is a talking state
3. selected outfit's `defaultIdle`
4. default outfit equivalent state
5. default outfit `defaultIdle`

A missing optional/private asset pack should therefore degrade to a bundled/default outfit without requiring code changes.

## File size and runtime budget

The asset pipeline should optimize for local iPhone playback rather than archival quality.

Guidance per 1080x1920/30fps clip:

- Prefer visually clean HEVC at roughly 2-5 Mbps for normal clips.
- Short loops should normally remain within a few megabytes each.
- Avoid lossless/intermediate codecs in the app bundle.
- Keep generation masters outside the app runtime package.

The exact large-binary storage strategy is owned by #24. This specification only requires that runtime assets remain practical for local playback and that the manifest remains source-controlled.

## Production workflow

For each outfit/state:

1. Start from the approved Yujie reference image/LoRA/source assets.
2. Generate or select a still/reference frame matching the canonical framing.
3. Generate a short image-to-video clip with restrained motion appropriate for the state.
4. Check identity, framing, lighting, and background against the outfit reference.
5. Trim/re-time the clip to the target duration.
6. For loop states, adjust the edit/generation until the boundary is not obvious in normal playback.
7. Remove audio.
8. Encode the runtime copy to HEVC 1080x1920/30fps.
9. Name the file according to the state catalog.
10. Update the manifest and record generation/source notes outside the runtime binary when needed for reproduction.

Do not change runtime code to compensate for a poorly matched asset; fix the asset instead.

## Acceptance checklist for generated clips

A clip is compatible when all applicable checks pass:

- 1080x1920 portrait, 30 fps.
- HEVC runtime delivery file.
- No embedded speech/audio required.
- Correct outfit/state filename and manifest entry.
- Yujie identity is consistent with the approved references.
- Camera/background/lighting match the rest of the outfit set.
- Loop states do not show an obvious hard cut during normal viewing.
- Talking clips look plausible with arbitrary independent TTS audio.
- No runtime code change is required to replace placeholder media with the final clip.

## Relationship to other issues

- #11 consumes the manifest and placeholder/final clips.
- #14 produces the first complete Yujie base set using this specification.
- #15 adds outfit sets and the wardrobe manifest implementation.
- #18 reuses the same web/avatar asset contract in PWA mode.
- #24 decides where large final binary packs are stored/distributed.

This document intentionally does not define backend, session, tool, STT, or TTS behavior.