# SoulNest Local Build, Signing and Install Runbook

This runbook prepares #25 without adding a public release pipeline. It reuses the upstream OpenMinis build process and adds only SoulNest-specific checks.

## 1. Fresh checkout

```sh
git clone --recurse-submodules https://github.com/WildenChen/OpenMinis.git
cd OpenMinis
```

For an existing checkout:

```sh
git switch main
git pull --ff-only
git submodule update --init --recursive
```

## 2. Local customization file

Create the ignored iOS customization file from the template:

```sh
cp src/ios/Configs/ProviderCustomization.xcconfig.example \
   src/ios/Configs/ProviderCustomization.xcconfig
```

Do not commit local credentials, signing values or backend secrets.

## 3. iOS native prerequisites

Follow `BUILDING.md`. On the build Mac, install the required tooling and build native dependencies in the upstream-defined order:

```sh
./deps/build_lame.sh
./deps/build_ffmpeg.sh
./deps/build_ish.sh
./deps/prepare_alpine_rootfs.sh
```

These outputs are local build artifacts and should remain uncommitted.

## 4. SoulNest identity preflight

Before attempting side-by-side installation, #19 must provide distinct identifiers for the app and extensions. Verify all related identifiers together rather than changing only the main app.

Expected identity family once #19 lands:

```text
main app:      com.wildenstudio.soulnest
share:         com.wildenstudio.soulnest.ShareExtension
file provider: com.wildenstudio.soulnest.FileProvider
widget:        com.wildenstudio.soulnest.AgentWidget
app group:     group.com.wildenstudio.soulnest
```

The final iCloud container identifier must match the provisioning capability actually created for the developer team. Do not invent/commit a container entitlement that cannot be provisioned.

Also verify any hard-coded app-group/FileProvider-domain identifiers were updated consistently; bundle-ID changes alone are insufficient.

## 5. Signing

Open:

```sh
open src/ios/Minis.xcodeproj
```

Use the `Minis` scheme and select the intended Apple Developer Team under Signing & Capabilities for the main app and every embedded extension that requires signing.

Do not commit personal team IDs or provisioning profiles unless the repository intentionally adopts a team-independent configuration later.

## 6. Unsigned compile check

A generic device compile can be used before signing when native dependencies are present:

```sh
xcodebuild -project src/ios/Minis.xcodeproj \
  -scheme Minis \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Use a device destination. The normal native dependency scripts build iOS/device arm64 artifacts, not simulator artifacts.

### LiveContainer package with private Avatar media

GitHub Actions intentionally has no access to private Yujie media and produces
the bundled-placeholder variant. After making an unsigned archive locally,
package a LiveContainer IPA with the private pack in one command:

```sh
python3 scripts/package_soulnest_livecontainer_ipa.py \
  build/SoulNest.xcarchive/Products/Applications/Minis.app \
  "$HOME/Library/Application Support/SoulNest/AvatarAssets/yujie-v1" \
  build/SoulNest-LiveContainer-yujie.ipa
```

The pack is copied only into the IPA's `Payload/SoulNest.app/Avatar` bundle;
it is not added to Git. If the pack is absent, use the normal GitHub/local
unsigned IPA instead: its bundled placeholder clips remain functional.

## 7. Physical-device install

After the unsigned compile check succeeds:

1. Connect the target iPhone.
2. Select the physical device in Xcode.
3. Confirm signing resolves for app + Share + FileProvider + Widget targets.
4. Build and Run.
5. Confirm SoulNest can coexist with upstream OpenMinis if both are installed.
6. Launch every extension entry point that is relevant to the MVP and confirm shared-container access still works.

## 8. Backend configuration

Configure OpenClaw only through the supported #4 settings/Keychain path once it is implemented.

Never place the OpenClaw Gateway bearer token in:

- `ProviderCustomization.xcconfig`
- source files
- UserDefaults
- Avatar/PWA assets
- committed JSON/plist files

Use the private-network guidance in `docs/security/soulnest-backend-security.md`.

## 9. Acceptance handoff

After installation, execute `docs/testing/soulnest-iphone-e2e.md` and record only non-sensitive evidence.

#25 can close when a clean checkout can be prepared, built and signed for a physical iPhone; SoulNest installs distinctly with its extensions; no identifier/app-group collision remains; and no secret must be committed to reproduce the build.

## Non-goals

- Public App Store/TestFlight automation.
- A new CI farm.
- Committing native build products.
- Simulator-specific dependency work unless a concrete test requires it.
- Signing/profile automation tied to one developer account.
