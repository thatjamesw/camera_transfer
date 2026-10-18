import plistlib
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from verify_app_bundle import verify


class PackageChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "scripts").mkdir()
        shutil.copy(ROOT / "scripts/build_app_bundle.sh", self.root / "scripts")
        shutil.copytree(ROOT / "dist/Camera Media Importer.app", self.root / "dist/Camera Media Importer.app")
        self.archive = self.root / "dist/Camera Media Importer.zip"
        shutil.copy(ROOT / "dist/Camera Media Importer.zip", self.archive)

    def replace_archive_entry(self, name, data):
        replacement = self.archive.with_suffix(".new.zip")
        with zipfile.ZipFile(self.archive) as source, zipfile.ZipFile(replacement, "w") as destination:
            for entry in source.infolist():
                destination.writestr(entry, data if entry.filename == name else source.read(entry))
        replacement.replace(self.archive)

    def test_valid_package(self):
        verify(self.root)

    def test_wrong_release_tag(self):
        with self.assertRaisesRegex(ValueError, "Release tag"):
            verify(self.root, "v0.0.0")

    def test_wrong_bundle_version(self):
        path = self.root / "dist/Camera Media Importer.app/Contents/Info.plist"
        info = plistlib.loads(path.read_bytes())
        info["CFBundleVersion"] = "0.0.0"
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "Bundle version"):
            verify(self.root)

    def test_stale_zip_metadata(self):
        self.replace_archive_entry("Camera Media Importer.app/Contents/Info.plist", b"stale metadata")
        with self.assertRaisesRegex(ValueError, "ZIP metadata"):
            verify(self.root)

    def test_stale_zip_executable(self):
        self.replace_archive_entry("Camera Media Importer.app/Contents/MacOS/CameraFileSortSwift", b"stale executable")
        with self.assertRaisesRegex(ValueError, "ZIP executable"):
            verify(self.root)
