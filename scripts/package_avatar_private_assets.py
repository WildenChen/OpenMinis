#!/usr/bin/env python3
"""Stage a versioned private Avatar pack next to the shared PWA manifest."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Private pack directory, e.g. AvatarAssets/yujie-v1")
    parser.add_argument("--avatar-dir", type=Path, default=Path("src/ios/Resources/Avatar"))
    args = parser.parse_args()

    source = args.source.expanduser().resolve()
    if not source.is_dir() or not (source / "casual" / "idle_01.mp4").is_file():
        raise SystemExit("source must contain casual/idle_01.mp4")
    destination = args.avatar_dir.resolve() / "assets" / "videos" / source.name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns("*.source.mp4", "stills"))
    print(destination)


if __name__ == "__main__":
    main()
