# Camera Media Transfer Wizard

Native macOS SwiftUI app for importing camera cards and other removable media into organized destination folders.

## What It Does

- Detects mounted removable volumes under `/Volumes` using common media roots like `DCIM` and `PRIVATE`.
- Lets you add manual sources with `Choose Source…` for drones, SSDs, or other folders that are not auto-detected.
- Imports photos, videos, or both into date-based folders.
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

## Current Workflow

1. Connect one or more SD cards, camera volumes, or external drives.
2. Optionally use `Choose Source…` to add a manual source folder or drive.
3. Pick the destination folder.
4. Optionally save that destination with `Set default`.
5. Choose transfer settings.
6. Click `Import`.

## Build

Build a standalone `.app` bundle:

```bash
./scripts/build_app_bundle.sh
```

Output:

- `dist/Camera Media Transfer Wizard.app`
- `dist/Camera Media Transfer Wizard.zip`

You can also run the package directly:

```bash
swift run
```

## Distribution Notes

If you share the app zip with other Macs, Gatekeeper may block it unless it is signed and notarized.
As a workaround for trusted users:

```bash
xattr -rd com.apple.quarantine "/path/to/Camera Media Transfer Wizard.app"
```

## Settings Storage

Settings are stored in `UserDefaults` under:

- `CameraFileSortSwift.Settings`
- `CameraFileSortSwift.DefaultRoot`

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
