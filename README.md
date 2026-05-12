# Camera Media Importer

Native macOS SwiftUI app for importing camera cards and other removable media into organized destination folders.

## What It Does

- Detects mounted removable volumes under `/Volumes` using common media roots like `DCIM` and `PRIVATE`.
- Lets you add manual sources with `Choose Source…` for drones, SSDs, or other folders that are not auto-detected.
- Imports photos, videos, or both into date-based folders.
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
- Tracks prior imports with a destination manifest to improve duplicate detection.
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
4. Pick the destination folder.
5. Optionally save that destination with `Set default`.
6. Choose folder organization, date source, media type, action, duplicate policy, and eject behavior.
7. Optionally scan media to preview counts.
8. Click `Import`.

## Import Behavior

- Destination folders are created automatically when needed.
- Duplicate detection checks destination file paths, files seen in the same pending import, and signatures from the destination manifest.
- `Skip` leaves duplicate files untouched.
- `Keep both` writes a numbered filename such as `IMG_0001_1.JPG`.
- `Overwrite` replaces the existing destination file.
- Source selection and import settings are locked while an import is running.

## Build

Build a standalone `.app` bundle:

```bash
./scripts/build_app_bundle.sh
```

Output:

- `dist/Camera Media Importer.app`
- `dist/Camera Media Importer.zip`

You can also run the package directly:

```bash
swift run
```

## Distribution Notes

If you share the app zip with other Macs, Gatekeeper may block it unless it is signed and notarized.
As a workaround for trusted users:

```bash
xattr -rd com.apple.quarantine "/path/to/Camera Media Importer.app"
```

## Settings Storage

Settings are stored in `UserDefaults` under:

- `CameraFileSortSwift.Settings`
- `CameraFileSortSwift.DefaultRoot`

Import manifests are stored in the selected destination root:

- `.camera_transfer_manifest.json`

## Defaults

- Destination: empty until you choose one or save a default
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
