# Camera Media Importer

Native macOS SwiftUI app for importing camera cards and other removable media into organized destination folders.

## What It Does

- Detects mounted removable volumes under `/Volumes` using common camera roots like `DCIM`, `PRIVATE`, `AVCHD`, `MP_ROOT`, `M4ROOT`, `XDROOT`, `CLIP`, and `CONTENTS`.
- Lets you add manual sources with `Choose Source…` for drones, SSDs, or other folders that are not auto-detected.
- Imports photos, videos, or both into date-based folders.
- Supports common camera, drone, action camera, and 360 media from brands such as Canon, Nikon, Sony, Fujifilm, Ricoh/Pentax, DJI, GoPro, Insta360, Panasonic, Olympus/OM System, Leica, Hasselblad, and RED.
- Carries matching same-folder sidecar files such as `.xmp`, `.xml`, `.srt`, `.lrf`, `.lrv`, `.thm`, and `.wav` along with their primary media file.
- Copies or moves selected media.
- Supports duplicate handling: prompt, skip, keep both, or overwrite.
- Supports destination modes:
  - separate `photo` / `video` folders
  - one shared folder
  - custom folder names
- Supports date source modes:
  - import date
  - file date
  - none
- Shows per-card and overall progress.
- Watches mount, unmount, and rename events from macOS and refreshes sources automatically.
- Uses native macOS eject handling after transfer and reports eject failures in the completion dialog.
- Checks existing destination paths for duplicates; old import manifests cannot cause missing files to be skipped.
- Ejects matching camera companion volumes, such as `PMHOME`, when they belong to the same removable device.

## Interface

The app is organized around three workflow areas:

- `Sources`: detected camera cards, manually chosen source folders, scan action, and source summary.
- `Destination`: destination folder, folder organization, date pattern, output preview, and transfer settings.
- `Run`: current status, per-card and overall progress, current file, import action, and open destination action.

The default window opens at a fitted native size so the controls are visible without scrolling. If you manually resize the window shorter, the main setup and run areas fall back to scrolling rather than clipping controls.

## Current Workflow

1. Connect one or more SD cards, camera volumes, or external drives.
2. Optionally use `Choose Source…` to add a manual source folder or drive.
3. Select the sources to import from.
4. Choose the device in Sources: Sony A1 II, DJI Avata 2, DJI Mini 5 Pro, DJI Pocket 4 Pro, or Misc.
5. Choose your import folder once, such as `/Volumes/kuva/import`. It is remembered automatically. Use `Change…` to choose a different folder.
6. Review the output. Expand `Import options` to adjust organization, dates, media, duplicate policy, or eject behavior.
7. Optionally scan media to preview counts.
8. Click `Import`.

## Import Behavior

- Destination folders are created automatically when needed.
- Duplicate detection checks destination paths and filename collisions in the same pending import. Matching filename, size, or timestamp alone is not treated as proof of a previous import.
- Related sidecars are imported only when they share the same base filename as a matched photo or video file in the same folder.
- `Skip` leaves duplicate files untouched.
- `Keep both` writes a numbered filename such as `IMG_0001_1.JPG`.
- `Overwrite` replaces the existing destination file.
- Source selection and import settings are locked while an import is running.

## Supported Media

Photo and raw formats include common JPEG/HEIF/TIFF/PNG files plus camera raw formats such as `.arw`, `.cr2`, `.cr3`, `.dng`, `.gpr`, `.insp`, `.nef`, `.nrw`, `.orf`, `.pef`, `.raf`, `.raw`, `.rw2`, `.sr2`, `.srf`, and `.x3f`.

Video formats include `.mp4`, `.mov`, `.mxf`, `.mts`, `.m2ts`, `.insv`, `.braw`, `.crm`, `.r3d`, `.avi`, `.m4v`, `.mpeg`, and related camera/video container formats.

## Build

Build a standalone `.app` bundle:

```bash
./scripts/build_app_bundle.sh
```

Output:

- `dist/Camera Media Importer.app`
- `dist/Camera Media Importer.zip`

Run filesystem regression checks through the shell helper:

```bash
./scripts/check.sh
```

## Distribution Notes

If you share the app zip with other Macs, Gatekeeper may block it unless it is signed and notarized.
The shell build signs the app with the Hardened Runtime and verifies the signature before packaging it with macOS `ditto`. Local builds use ad-hoc signing. Set `CAMERA_SIGN_IDENTITY` to a Developer ID Application identity for distribution signing; Apple notarization remains a separate release step.

## Settings Storage

Settings are stored in the `com.jameswright.camerafilesort` `UserDefaults` domain under:

- `CameraFileSortSwift.Settings`
- `CameraFileSortSwift.DefaultRoot`

Older versions wrote `.camera_transfer_manifest.json` inside target folders. These legacy files are no longer read or written; they may be removed with the uninstall helper.

## Uninstall

The uninstall helper dry-runs by default so you can inspect what would be removed:

```bash
./scripts/uninstall.sh
```

Remove app preferences and known preference plist files:

```bash
./scripts/uninstall.sh --apply
```

Remove a destination manifest from a known import root:

```bash
./scripts/uninstall.sh --manifest-root "$HOME/Pictures/imports" --apply
```

Search common user media folders for `.camera_transfer_manifest.json` files and remove them:

```bash
./scripts/uninstall.sh --scan-manifests --apply
```

Also remove app bundles from `/Applications` and `dist`:

```bash
./scripts/uninstall.sh --remove-app --apply
```

## Defaults

- Destination: saved default on launch, or empty if none is saved
- Target: Misc initially; remembers your selected model
- Date format: `MMddyyyy`
- Action: copy
- Duplicates: prompt
- Eject after transfer: true
- Destination mode: separate folders
- Media selection: photo + video

## Notes

- Auto-detection is focused on removable media and common camera folder structures.
- Manual sources broaden support for devices like drones, SSDs, and other media folders.
- If no saved default destination exists, the destination field now starts empty on launch.
- The app bundle name is `Camera Media Importer`, while the Swift package and executable target remain `CameraFileSortSwift`.

## Target folders

With base `/Volumes/kuva/import` and target `Sony A1 II`, separate layout writes to `/Volumes/kuva/import/SonyA1II/photo` and `video`, followed by the date folder when enabled. Shared and custom layouts also live below the selected target. Choose the base import folder once, rather than an existing model folder. The selected target applies to all sources in that import; import different models in separate runs.

Existing preferences remain readable. The last temporary destination no longer overrides the saved default. The destination is now one remembered import folder; there is no separate default-setting step.

## Manage devices

Use **Manage devices…** below the device picker in Sources to add, rename, or remove devices. New devices are selected automatically. Names must be unique and valid folder names. Renaming changes the folder used for future imports; existing folders and media are untouched. Removing a device only removes its list entry. Keep at least one device. The device list and selection are saved automatically, and existing built-in selections are preserved on upgrade.

Device display names retain spaces, while generated folder names omit whitespace: `Sony A1 II` → `SonyA1II`. Existing folders are not renamed. New or renamed devices cannot share the same generated folder name.
