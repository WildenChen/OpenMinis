# SoulNest Backend Security Boundary

## Purpose

Define the minimum safe boundary for SoulNest connecting OpenMinis on iPhone to external agent backends such as OpenClaw and Hermes.

SoulNest is a trusted personal client, but that does not make backend credentials low-risk. The mobile app must keep backend secrets out of normal preferences, logs, WebApp assets, and public network exposure.

## OpenClaw credential sensitivity

The OpenClaw Gateway `/v1/chat/completions` bearer token/password path is an owner/operator credential. Possession can authorize the normal Gateway agent path and the target agent's allowed host-side tools.

Therefore:

- never store the Gateway token in `UserDefaults`
- never commit it to the repository or build-time example files
- never include it in Avatar HTML/JS/manifest/PWA assets
- never print the token in logs, diagnostics, crash breadcrumbs, or request dumps
- never expose an unauthenticated public proxy that injects the token on behalf of arbitrary callers

PR #33 intentionally removed plaintext Gateway-token persistence. Secure persistence belongs to #4.

## iOS secret storage

For MVP, store backend secrets in Keychain using a dedicated SoulNest/backend credential item. Prefer a device-local Keychain item for owner-level self-hosted credentials rather than silently syncing it through ordinary preferences.

Recommended properties:

- service scoped to SoulNest + backend
- account/key scoped to the configured backend instance
- no value copied into `UserDefaults`
- no value exposed through observable UI state longer than necessary
- deletion when the backend configuration is removed
- replace/update atomically when the credential changes

Whether a credential is synchronizable across Apple devices must be an explicit design choice. Do not inherit iCloud Keychain synchronization merely because another provider helper happens to use it.

Base URL, backend kind, and non-secret target/profile/agent IDs may use normal app configuration.

## Network exposure

For a self-hosted OpenClaw/Hermes backend, prefer a private connectivity boundary:

1. same trusted private LAN when appropriate
2. Tailscale/tailnet or equivalent private overlay
3. authenticated private ingress/reverse proxy

Do not expose the OpenClaw owner/operator HTTP endpoint directly to the public Internet merely to make SoulNest mobile access convenient.

If traffic leaves a trusted local/private network, use TLS through the chosen private ingress. Do not weaken App Transport Security globally for SoulNest. Any exception must be narrowly scoped to the explicit local-development endpoint and reviewed before release.

## OpenClaw session/tool boundary

The mobile/backend trust boundary is also a tool boundary:

- `minis_*` tools are caller-supplied capabilities of the current iPhone and execute inside OpenMinis
- OpenClaw-native tools execute on the OpenClaw host
- OpenClaw internal tools are not renamed or proxied through the phone
- tool results return with the matching `tool_call_id` in the same stable backend session

The adapter policy may explain this distinction, but correctness is enforced by the reversible wire namespace implemented in PR #33.

## Authentication failure behavior

Authentication/configuration failures must be explicit and recoverable.

Examples:

- missing credential → show backend-not-configured/auth-required state
- `401`/`403` → report authentication/authorization failure; do not silently switch to another LLM/backend
- unreachable private host → report connectivity failure and keep the same OpenMinis chat/session identity for retry
- malformed/expired configuration → allow the user to edit or remove the backend configuration

A failed OpenClaw request must never silently fall back to Hermes or a raw OpenMinis provider under the same conversation identity.

## Avatar WebApp / PWA boundary

The Avatar presentation layer is not a credential holder.

- bundled Avatar HTML/CSS/JS must not read Keychain credentials
- do not inject backend tokens into JavaScript globals, query strings, localStorage, IndexedDB, manifests, or service-worker caches
- a standalone PWA must use its own supported backend/auth mechanism and must not receive native SoulNest secrets
- if the native Avatar WebView needs backend interaction, use a SoulNest-specific native bridge that passes only scoped presentation/input events; keep transport credentials and requests native-side
- do not weaken generic OpenMinis WebApp sandbox/security policy just to support SoulNest

## Hermes boundary

Hermes should follow the same rules when #6 lands:

- credential stored in Keychain, not preferences/WebApp assets
- use the narrowest supported API credential/scope
- private/authenticated network ingress preferred
- backend-native tools remain server-side
- OpenMinis tools remain phone-side
- no silent backend fallback

Update this document once the concrete Hermes transport/auth contract is implemented.

## Configuration UI requirements (#4)

The minimal backend settings flow should expose only what is needed:

- backend type
- backend URL/host
- target agent/profile ID
- credential entry/update/remove
- explicit activate/deactivate/switch action

The UI may display whether a credential exists, but must not redisplay the stored secret after save.

Do not add advanced Gateway model overrides, arbitrary headers, public proxy controls, or secret-export UI for MVP.

## Release checklist

Before #20 can close, verify:

- [ ] backend secrets are Keychain-backed
- [ ] no backend secret is persisted in `UserDefaults`
- [ ] logs/errors do not contain the secret
- [ ] Avatar WebApp/PWA assets cannot access native backend secrets
- [ ] auth errors are explicit and do not trigger silent backend fallback
- [ ] recommended network setup is private/authenticated
- [ ] no global WebApp/ATS security weakening was introduced
- [ ] OpenClaw real-device connection is exercised with a non-public endpoint
- [ ] Hermes-specific credential handling is reviewed when #6 lands
