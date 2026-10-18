#!/usr/bin/env python3
"""Verify the shell build's app and ZIP, optionally against a release tag."""
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def verify(root, tag=""):
    app_name = "Camera Media Importer.app"
    app = root / "dist" / app_name
    archive = root / "dist" / "Camera Media Importer.zip"
    version = re.search(r'^APP_VERSION="([^"]+)"$',
                        (root / "scripts/build_app_bundle.sh").read_text(), re.MULTILINE).group(1)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != version:
        raise ValueError("Bundle version does not match the build script")
    if tag and tag != "v" + version:
        raise ValueError(f"Release tag {tag} does not match bundle version v{version}")
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    subprocess.run(["unzip", "-tq", str(archive)], check=True)
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(["ditto", "-x", "-k", str(archive), directory], check=True)
        packaged = Path(directory) / app_name
        if (packaged / "Contents/Info.plist").read_bytes() != (app / "Contents/Info.plist").read_bytes():
            raise ValueError("ZIP metadata differs from the built app")
        executable = Path("Contents/MacOS/CameraFileSortSwift")
        if (packaged / executable).read_bytes() != (app / executable).read_bytes():
            raise ValueError("ZIP executable differs from the built app")
        subprocess.run(["codesign", "--verify", "--strict", str(packaged)], check=True)
    print(f"Verified app and ZIP: v{version}")


if __name__ == "__main__":
    verify(Path(__file__).resolve().parent.parent, sys.argv[1] if len(sys.argv) > 1 else "")
