# Camera File Sort (SwiftUI)

Native macOS SwiftUI app that imports Sony A1II cards into date-based folders.

## Features

- Detects mounted cards in `/Volumes` (looks for `DCIM` or `PRIVATE`).
- Imports to `/Users/jameswright/Desktop/kuva/import/a1ii/<folder>/<DATE>` (configurable).
- Duplicate handling: prompt, skip, keep both, overwrite.
- Destination path picker.
- Per-card and overall progress.
- Media selection (photo, video, photo+video).
- Destination mode (separate, same, or custom folder names) plus custom folder names.
- Optional auto-eject, including Sony `PMHOME`.

## Build & Run

Open the Swift package in Xcode:

1. Open Xcode.
2. File > Open… and select the `swift_app` folder.
3. Select the `CameraFileSortSwift` scheme and run.

You can also run from the command line:

```bash
cd /Users/jameswright/dev/_mvp/camera_file_sort/swift_app
swift run
```

Note: For the SwiftUI app UI, Xcode is recommended.

## Standalone .app (no Xcode project required)

This builds a macOS `.app` bundle from the SwiftPM release binary.

```bash
/Users/jameswright/dev/_mvp/camera_file_sort/swift_app/scripts/build_app_bundle.sh
```

The resulting app is:

`/Users/jameswright/dev/_mvp/camera_file_sort/swift_app/dist/Sony Camera Media Transfer Wizard.app`

## Settings

Settings are stored in `UserDefaults` under the key `CameraFileSortSwift.Settings`.

## Defaults

- Destination: `/Users/jameswright/Desktop/kuva/import/a1ii`
- Date format: `MMddyyyy` (e.g. 03022026)
- Action: copy
- Duplicates: prompt
- Eject after transfer: true

## Next steps

- Add delete confirmation for cards list and presets if reintroduced.
- Add full path preview for photo/video/audio destination folders.
