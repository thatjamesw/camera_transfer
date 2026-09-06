# App review — 6 September 2026

Reviewed the SwiftUI interface, application state, settings and migration, scanner, importer, eject handling, shell build, icon helper, uninstall helper, and regression checks. Fixed the issues below and built version 1.7.0 through `scripts/build_app_bundle.sh`.

This is a source review plus automated and UI smoke testing, not a guarantee that the app is defect-free.

## Findings addressed

| Area | Finding | Resolution |
| --- | --- | --- |
| Import lifecycle | Dismissing the duplicate-policy dialog could clear the importing flag after transfer started. | Explicit choice sheet; the transfer stays locked until completion. |
| Duplicate detection | Filename/size/timestamp history could skip missing or unrelated files. | Removed metadata-only manifest decisions. Duplicate policies operate on destination paths; old manifests are untouched and ignored. |
| Destination safety | Custom names, corrupted device names, or symlinked folders could direct writes outside the intended device folder. | Validate folder/date settings and resolved output containment before writing; reject device-folder symlinks, non-file targets, and overlapping source/output trees. |
| Failed writes | Ordinary copies could expose an incomplete final file. | Coordinate file access, copy to a unique staging file on the destination filesystem, check size/source modification metadata, then commit. Existing files use Foundation replacement. Move removes the source only after commit. |
| Scan errors | Unreadable/missing sources and enumeration failures could look like an empty successful scan. | Retain and surface scan errors; abort the import if a scan is incomplete. |
| Sidecars | Keep-both could number a photo without giving its sidecar the same suffix. | Reserve compatible group filenames before transfer. |
| Progress | Different source folders with the same displayed name could push per-card progress beyond 100%. | Reset per-card counters at each source; throttle UI updates to roughly 10 per second. |
| State isolation | Background work could outlive the settings/date used by the initial scan. | Main-actor UI state and an immutable settings/import-date snapshot across scan, duplicate choice, and transfer. Single app window avoids competing editors. |
| Scan performance | Sidecar matching repeatedly read directories and rebuilt extension sets. | Collect sidecars in the source enumeration; group cached results by folder and basename. |
| Transfer performance | A serial queue allocated one operation per file and repeatedly constructed date formatters. | Serial worker loop with an autorelease pool per file and a reused formatter using Gregorian/POSIX date formatting. |
| Volume handling | Discovery could block the main actor, detached destinations could be treated as creatable paths, and eject subprocess pipes could block. | Asynchronous discovery with stale-result protection; missing-volume checks; drain subprocess output before waiting, with a 30-second termination watchdog. |
| Ejection | A destination volume or failed import could be ejected. | Keep failed imports mounted; validate ejectability and reject ejection of a volume containing the output. |
| Packaging | Bundle resources were not explicitly signed and verified by the build script. | Hardened Runtime signing and strict verification before macOS ditto ZIP packaging. Local signature is ad-hoc. |

## Verification

- Release build: `./scripts/build_app_bundle.sh` — passed without compiler warnings.
- Optimized checks: `./scripts/check.sh --performance` — passed.
- Debug checks were also used while investigating file coordination.
- Shell syntax checks and `git diff --check` — passed.
- `codesign --verify --strict` — passed. Signature flags include `adhoc,runtime`.
- UI smoke check: app launch, device-name routing preview, expanded import options and scrolling.
- Automated coverage includes all device targets, legacy settings, device management, no-space names, multiple cards, regular-file filtering, sidecars, skip/keep-both/overwrite, preservation after failed overwrite, move commits, missing sources, stale manifests, path traversal, device symlinks, source/output overlap, same-name card progress, and duplicate-choice state.

The file-coordination checks require normal macOS service access. A confined execution environment blocked these services and reported file-open failures; the same tests passed outside that environment. No production bypass was added.

### Performance sample

Optimized local APFS run on this Mac:

- 1,000 small photo files, 1,000 matching sidecars, and 50 one-MiB videos.
- Total: 2,050 files.
- Scan: **0.099 seconds**.
- Copy: **2.386 seconds**.

This is a synthetic local-storage smoke benchmark. APFS cloning and caches may help it substantially. It is not a measurement of sustained camera-card, USB, network-volume, or multi-gigabyte video throughput, and no before/after speedup is claimed.

## Remaining limits and release work

- Physical card removal, real eject behavior, full-disk failure, network/file-provider interruption, sudden power loss, and macOS 13 hardware were not exercised.
- Staging verifies file size and source modification metadata, not a full cryptographic readback. It does not prove storage-media integrity.
- File coordination helps with cooperating apps. The importer is not designed as a security boundary against a hostile process running as the same user and racing filesystem changes.
- The app is not App Sandbox-enabled. It uses the user's existing filesystem permissions and has no network client, telemetry, downloaded code, or third-party package dependencies in the reviewed source.
- Some small destination checks still use synchronous filesystem calls; slow or unavailable network storage can delay those interactions.
- Developer ID signing and Apple notarization are still needed for normal public distribution. The build supports `CAMERA_SIGN_IDENTITY`; ad-hoc signing does not establish a trusted developer identity.
- Keep-both naming and old-manifest behavior have changed deliberately. Existing media folders and legacy manifest files are not moved or deleted.

## Apple guidance consulted

- [Improving performance and stability when accessing the file system](https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system)
- [FileManager replacement](https://developer.apple.com/documentation/foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:))
- [Coordinating reads and writes](https://developer.apple.com/documentation/foundation/nsfilecoordinator/coordinate(readingitemat:options:writingitemat:options:error:byaccessor:))
- [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
