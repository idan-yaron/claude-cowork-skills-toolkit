#!/usr/bin/env python3
"""Package skills-toolkit as .zip with correct forward-slash paths."""

import os
import zipfile
from pathlib import Path

PLUGIN_ROOT = Path(__file__).parent
DIST_DIR = PLUGIN_ROOT / "dist"
PLUGIN_NAME = "skills-toolkit"

EXCLUDE_DIRS = {".git", "dist", "docs", "node_modules", "__pycache__"}
EXCLUDE_FILES = {"build.py", ".gitignore"}
EXCLUDE_EXTENSIONS = {".zip"}


def should_include(path: Path) -> bool:
    parts = path.relative_to(PLUGIN_ROOT).parts
    if any(part in EXCLUDE_DIRS for part in parts):
        return False
    if path.name in EXCLUDE_FILES:
        return False
    if path.suffix in EXCLUDE_EXTENSIONS:
        return False
    return True


def main():
    DIST_DIR.mkdir(exist_ok=True)
    zip_path = DIST_DIR / f"{PLUGIN_NAME}.zip"

    zip_path.unlink(missing_ok=True)

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(PLUGIN_ROOT):
            dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
            for file in files:
                full_path = Path(root) / file
                if not should_include(full_path):
                    continue
                arc_name = full_path.relative_to(PLUGIN_ROOT).as_posix()
                zf.write(full_path, arc_name)

    print(f"Contents of {zip_path.name}:")
    with zipfile.ZipFile(zip_path, "r") as zf:
        for info in zf.infolist():
            print(f"  {info.filename}  ({info.file_size} bytes)")

    size = zip_path.stat().st_size
    print(f"\nPackaged ({size:,} bytes):")
    print(f"  {zip_path}")


if __name__ == "__main__":
    main()
