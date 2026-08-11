# SoulNest Avatar PWA

The files in this directory are the shared SoulNest Avatar presentation package. The same HTML/CSS/JS/manifest is bundled in the iOS app and can also be served as a standalone installable PWA for UI/asset testing.

## Run standalone

Serve this directory over `https://` or localhost. For a quick local test from the repository root:

```sh
cd src/ios/Resources/Avatar
python3 -m http.server 8080
```

Then open `http://localhost:8080/` in a browser. Installability depends on browser/platform PWA rules; production hosting should use HTTPS.

## Offline behavior

`service-worker.js` precaches the presentation shell (`index.html`, CSS, JS, the Avatar manifest, PWA manifest and icon). Same-scope Avatar assets are cached lazily after first successful fetch. The cache intentionally stays scoped to this Avatar directory so a future backend/API request is not cached accidentally.

## Transport boundary

The PWA is a presentation surface, not a second agent runtime.

- OpenMinis-hosted mode remains the primary path for native iPhone capabilities.
- The standalone PWA must not contain or persist OpenClaw/Hermes owner credentials.
- Do not call OpenClaw directly from browser JavaScript with the Gateway bearer token.
- A future supported standalone backend path must use an authenticated bridge/proxy with least-privilege credentials; it may drive the existing `window.SoulNestAvatar` presentation API.
- The native OpenMinis host connects backend events to `window.SoulNestAvatar` without exposing native secrets to Web content. In the bundled WKWebView it additionally accepts only two one-way UI intents (`send` text and `mic`); native code routes them through the existing chat/STT path. The page cannot select a provider, inspect session identifiers, or make backend requests.

In standalone PWA mode (no native handler), send/microphone controls remain local visual demo behavior. This keeps the reusable package installable/offline without duplicating HealthKit, HomeKit, Location, Calendar, Photos, Speech, Native Offloads or other OpenMinis capabilities in JavaScript.

## Presentation API

The existing shell exports `window.SoulNestAvatar`, including:

- `setState(state)`
- `selectOutfit(outfit)`
- `setSubtitle(text)` / `clearSubtitle()`
- `say(text)`
- `getState()` / `getOutfit()`

Backend/native integration should drive these presentation calls rather than create a second Avatar implementation.
