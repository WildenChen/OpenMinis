# SoulNest iPhone End-to-End Acceptance Runbook

This runbook is the physical-device acceptance checklist for #22. It is intentionally ordered from cheapest/high-signal checks to later presentation/release checks.

## Preconditions

- Use a physical iPhone build of the current `main` branch.
- External Agent Backend foundation and OpenClaw adapter are present.
- Configure OpenClaw through the supported #4 settings/credential path once it lands; do not inject production credentials into source files.
- The intended OpenClaw agent is Yujie.
- Location and Calendar permissions may be granted during the test.
- Keep one known-good OpenClaw-native tool available for the server-side ownership check.

## Record for every run

Capture:

- SoulNest commit SHA.
- iOS version/device model.
- OpenClaw version and target agent ID.
- Network path (LAN/Tailscale/private ingress).
- Whether Location/Calendar permissions were already granted.
- Pass/fail plus the smallest useful error/log note for each step.

Do not record bearer tokens, API keys, private calendar contents, precise location coordinates, Health data, or other sensitive payloads in committed test evidence.

## Core backend/session sequence

1. Launch SoulNest and create chat A.
2. Send a simple text prompt that does not require tools.
3. Confirm the answer is streamed from OpenClaw Yujie rather than a local placeholder/provider fallback.
4. Send a second prompt in chat A that depends on the prior answer; confirm continuity.
5. Create chat B and send a prompt.
6. Confirm B does not inherit A's conversation context.
7. Return to chat A and ask a follow-up; confirm A resumes its original OpenClaw session.
8. Trigger a normal retry/reconnect condition and confirm chat A still resumes the same backend session.

Expected routing invariant:

```text
chat A -> soulnest:<A>
chat B -> soulnest:<B>
return A -> soulnest:<A>
```

A reconnect/retry must not silently create a new session key.

## Tool ownership and device roundtrip

### Location

1. In chat A, ask a question that genuinely requires the current iPhone location.
2. Confirm OpenClaw requests the namespaced OpenMinis client tool (`minis_*` on the wire).
3. Confirm OpenMinis executes the existing Location capability on-device.
4. Confirm the tool result returns with the same tool-call identity into the same OpenClaw session.
5. Confirm Yujie produces the final answer.

### Calendar

Repeat the same flow with the existing Apple Calendar capability. `minis_calendar_*` means the current iPhone/Apple Calendar surface; an OpenClaw/cloud calendar tool remains server-side.

### OpenClaw-native tool

Use one known OpenClaw-native tool and verify it executes entirely on OpenClaw. It must not be renamed to `minis_*` and must not be bounced back to the iPhone.

### Permission/error behavior

Deny one representative permission or induce one representative tool failure. The UI/backend should surface a useful failure without losing the chat session or silently switching providers.

## Avatar sequence

Once #12/#16/#17 are integrated:

1. Open the Avatar surface; Yujie is visible and idle.
2. Send text; state transitions `idle -> thinking -> talking -> idle`.
3. Subtitle text remains visible while the answer is presented.
4. Trigger at least one basic emotion state.
5. Switch between at least two outfit sets and confirm fallback behavior when an optional clip is unavailable.
6. A missing optional/private asset pack must fall back to bundled/default assets without breaking the conversation.

## Voice sequence

Once #16 is integrated:

1. Tap push-to-talk/microphone.
2. Speech-to-text produces usable text.
3. The recognized text goes through the same selected OpenClaw backend/session path.
4. The final textual answer is preserved even if TTS fails.
5. When TTS succeeds, Avatar talking state is active during playback and returns to idle afterwards.

## Reliability sequence

Once #10 is integrated:

- User stop/cancel does not leave the chat permanently stuck in streaming state.
- A transient network interruption is recoverable.
- Retry reuses the same backend session.
- Auth failure is distinguishable from timeout/backend unavailable/malformed stream/tool failure.
- No error path silently falls back to another backend/provider.

## Install/identity sequence

Once #19/#25 are integrated:

- SoulNest installs alongside upstream OpenMinis without bundle-ID collision.
- Share/FileProvider/Widget extensions install and address the SoulNest app group consistently.
- The installed app is visibly identified as SoulNest.
- No signing credential or backend secret is committed to Git.

## MVP pass criteria

#22 can close only when the physical-device run demonstrates the MVP scenarios tracked in #28: visible Avatar, OpenClaw text chat, A/B/return-A continuity, real Location and Calendar roundtrips, correct tool ownership, voice/TTS, Avatar state/emotions, two outfits, retry continuity, and distinct SoulNest installation.

Hermes is validated separately when #6 exists; lack of Hermes must not block proving the primary OpenClaw MVP path.
