#!/usr/bin/env python3
"""Make a LiveContainer IPA from an unsigned Minis.app and a private Avatar pack."""

from __future__ import annotations

import argparse
import plistlib
import shutil
import tempfile
import zipfile
from pathlib import Path


def stage_pack(source: Path, app: Path) -> None:
    built_in_videos = (
        Path("casual/idle_01.mp4"),
        Path("office/idle_01.mp4"),
    )
    if missing := [str(path) for path in built_in_videos if not (source / path).is_file()]:
        raise SystemExit(f"private pack is missing required built-in videos: {', '.join(missing)}")
    target = app / "Avatar" / "assets" / "videos" / source.name
    if target.exists():
        shutil.rmtree(target)
    for relative_path in built_in_videos:
        destination = target / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative_path, destination)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path, help="Unsigned Minis.app from xcodebuild/archive")
    parser.add_argument("pack", type=Path, help="Private yujie-v1 pack directory")
    parser.add_argument("output", type=Path, help="Output LiveContainer IPA path")
    args = parser.parse_args()

    app = args.app.expanduser().resolve()
    pack = args.pack.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if not app.is_dir() or not (app / "Info.plist").is_file():
        raise SystemExit("app must be an unsigned Minis.app bundle")
    if output.exists():
        raise SystemExit(f"output already exists: {output}")

    with tempfile.TemporaryDirectory(prefix="soulnest-livecontainer-") as temp:
        payload_app = Path(temp) / "Payload" / "SoulNest.app"
        payload_app.parent.mkdir()
        shutil.copytree(app, payload_app, symlinks=True)
        stage_pack(pack, payload_app)
        shutil.rmtree(payload_app / "PlugIns", ignore_errors=True)

        info_path = payload_app / "Info.plist"
        with info_path.open("rb") as f:
            info = plistlib.load(f)
        info["CFBundleIdentifier"] = "com.wildenstudio.soulnest"
        info["CFBundleName"] = "SoulNest"
        info["CFBundleDisplayName"] = "SoulNest"
        with info_path.open("wb") as f:
            plistlib.dump(info, f, sort_keys=False)

        output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output, "x", zipfile.ZIP_DEFLATED) as ipa:
            for path in (Path(temp) / "Payload").rglob("*"):
                ipa.write(path, path.relative_to(temp))
    print(output)


if __name__ == "__main__":
    main()
