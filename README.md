# Camera Media Transfer Wizard (SwiftUI)

Native macOS SwiftUI app that imports Sony A1II cards into date-based folders.

## Features

- Detects mounted cards in `/Volumes` (looks for `DCIM` or `PRIVATE`).
- Imports to `~/Pictures/Camera Imports/<folder>/<DATE>` by default (configurable).
- Duplicate handling: prompt, skip, keep both, overwrite.
- Destination path picker.
- Per-card and overall progress (with x/total count).
- Media selection (photo, video, photo+video).
- Destination mode (separate, same, or custom folder names) plus custom folder names.
- Date source selection (Import date / File date / None).
- Saved default destination location.
- Optional auto-eject, including Sony `PMHOME`.

## Build & Run

Open the Swift package in Xcode:

1. Open Xcode.
2. File > Open… and select the `camera_transfer` folder.
3. Select the `CameraFileSortSwift` scheme and run.

You can also run from the command line:

```bash
cd camera_transfer
swift run
```

Note: For the SwiftUI app UI, Xcode is recommended.

## Standalone .app (no Xcode project required)

This builds a macOS `.app` bundle from the SwiftPM release binary and zips it.

```bash
./scripts/build_app_bundle.sh
```

The resulting app is:

`dist/Camera Media Transfer Wizard.app`

The zip is:

`dist/Camera Media Transfer Wizard.zip`

## Distribution Notes

If you share the zip with other Macs, Gatekeeper may block it unless it’s signed + notarized.
As a workaround for trusted users, they can remove the quarantine attribute:

```bash
xattr -rd com.apple.quarantine "/path/to/Camera Media Transfer Wizard.app"
```

## Settings

Settings are stored in `UserDefaults` under the key `CameraFileSortSwift.Settings`.

## Defaults

- Destination: `~/Pictures/Camera Imports`
- Date format: `MMddyyyy` (e.g. 03022026)
- Action: copy
- Duplicates: prompt
- Eject after transfer: true

## Next steps

- Add delete confirmation for cards list if needed.
