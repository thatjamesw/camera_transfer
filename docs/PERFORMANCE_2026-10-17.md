# Local transfer benchmarks — 17 October 2026

Baseline: v2.1.1, commit `626e9f6`, optimized Swift compilation on this Apple Silicon Mac. Benchmarked temporary fixtures only; no camera card or user media was used.

## Measured candidate

The candidate only adds an incoming-filename filter to the prior-import index. It still enumerates the archive and handles symlinks as before. It avoids expensive output-path validation and index storage for filenames absent from the incoming batch. Matching candidates still undergo the original path validation and complete byte comparison; copy staging, coordination, overwrite handling, and move-source deletion are unchanged.

The candidate was benchmarked under `.build/transfer-bench/` before being applied to `Importer.swift`. The source change is included in v2.1.2.

## Five paired rounds

Each round ran baseline and candidate sequentially, alternating which ran first. Fixture generation and output reset were excluded. Times include source scanning, transfer counting, and the import itself, excluding fixture cleanup and ejecting. Every new or skipped destination was independently compared to its source after timing. All 40 runs passed their expected copy/skip counts and output comparisons.

Reported values are medians, in seconds. These are warm/cached local APFS measurements, not physical card throughput.

| Scenario | Baseline | Candidate | Interpretation |
| --- | ---: | ---: | --- |
| Fresh import: 1,000 photos + 1,000 sidecars + 50 one-MiB videos | 2.261 | 2.250 | No meaningful difference (0.5%) |
| Four written 64-MiB videos, fresh local APFS copy | 0.0089 | 0.0092 | No meaningful difference; cloning/caching dominates |
| 200 new files, destination archive contains 20,200 older files | 1.476 | 0.290 | **80.4% less elapsed time; 5.1× as fast** |
| 200 identical prior imports, destination archive contains 20,200 files | 1.315 | 0.135 | **89.7% less elapsed time; 9.7× as fast** |

Archive new-import totals ranged from 1.471–1.490 seconds for baseline and 0.285–0.303 for candidate. Archive repeat-import totals ranged from 1.308–1.336 and 0.134–0.140 seconds respectively. The improvement is substantially larger than the observed run-to-run variation.

The fresh small-file counting stage took only about 28 ms, versus about 2.26 seconds for the full operation. Reworking transfer-plan ownership is not justified by that measurement alone. No parallel-transfer or custom copy-engine change was tested.

## Copying without APFS cloning

Mounted a disposable 512-MiB HFS+ sparse disk image on the same Mac. Copied the four actually written 64-MiB videos from APFS to HFS+ using the baseline importer. Crossing filesystems prevents an APFS clone of the source data.

Three transfer-only results: **0.114, 0.220, 0.220 seconds** for 256 MiB. Median: **0.220 seconds**, approximately **1,164 MiB/s (1.14 GiB/s)**. Output contents were verified after every run. The scratch volume was unmounted afterward.

This is a cached logical-copy measurement. It excludes a durable flush to physical storage, uses a disk image backed by the same SSD, has only a 256-MiB working set, and includes a noticeably faster first run. It cannot establish sustained device throughput or predict an SD card, reader, USB hub, or external destination's speed.

## Correctness and evidence

Compiled the candidate with the full existing regression suite and ran its optimized `--performance` checks: passed. This includes prior-import byte comparison, changed/missing copies, every duplicate policy, sidecars, path containment, symlinks, interrupted sources, denied writes, failed-overwrite preservation, move-source preservation, and the 512-MiB comparison fixture.

Local generated evidence (ignored by Git):

- `.build/transfer-bench/results.json`: all 40 paired measurements.
- `.build/transfer-bench/cross-results.json`: the three non-cloned copy measurements.
- `.build/transfer-bench/Benchmarks.swift`: timed harness and output assertions.
- `.build/transfer-bench/Importer-baseline.swift` and `Importer-candidate.swift`: exact compared source snapshots.
- `.build/transfer-bench/prepare.py` and `run.py`: fixture generation and paired runner.
- `.build/transfer-bench/Benchmarks-Cross.swift`: disk-image destination variant.

For a local rerun from the repo root, regenerate fixtures with `python3 .build/transfer-bench/prepare.py`, then run `python3 .build/transfer-bench/run.py` with normal macOS file-coordination access. The compiled baseline and candidate executables are retained in that directory. The generated evidence is local rather than a committed benchmark framework.

Implemented the small archive-filename filter after benchmarking. Its measured benefit is reducing archive-validation overhead; it does not accelerate the underlying copy operation. Added a regression confirming case-insensitive matching of RAW and sidecar names while unrelated files exist in the archive. Profile real source/destination hardware before adding concurrent copying or replacing platform copy APIs.

## Follow-up: Sony A1 II-sized RAW batches

The user imports approximately 70-MB RAW files from a CFexpress Type A card inside a Sony A1 II connected directly to a MacBook.

Repeated five alternating baseline/candidate rounds using **20 actually written 70,000,000-byte `.ARW`-sized files plus 20 XMP sidecars**, about 1.4 GB per batch. These are synthetic random-pattern payloads, not decodable camera images; the app does not decode media during transfer. The archive had 20,000 unrelated metadata fixtures and 40 matching prior files. All 30 runs passed expected counts and independent output-content comparisons. Fixture creation and verification were outside timing.

| RAW-sized workload | Baseline median | Candidate median |
| --- | ---: | ---: |
| Fresh local APFS import, 20 RAW + 20 XMP | 0.0515 s | 0.0524 s |
| New batch with existing archive | 1.3211 s | 0.1181 s |
| Identical prior batch with existing archive | 1.3722 s | 0.1771 s |

The archive filter saved about 1.2 seconds per batch here. Fresh-copy timings are dominated by local APFS cloning and must not be read as 1.4 GB transferred over USB in 0.05 seconds. The candidate still reads matching source and destination contents fully when checking previous imports. A physical camera link can make those reads much slower, reducing the relative importance of the archive savings.

Sony documents [USB-C SuperSpeed USB 10 Gbps](https://helpguide.sony.net/ilc/2440/v1/en/contents/231h_specifications_ilc2440.html) for the A1 II and recommends [MassStorage(MSC), a compatible computer, and a 10-Gbps-capable cable](https://helpguide.sony.net/ilc/2440/v1/en/contents/0903_connection_pc.html) for high-speed transfers. This is an interface specification, not a measured sustained copy rate. No camera volume was mounted during these tests, so actual negotiated USB speed and camera-to-destination throughput remain unmeasured.

RAW measurements, harness, compiled variants, and runner are retained under `.build/transfer-bench/raw/` (ignored by Git). Generated media fixtures were removed after verification. The benchmarked filter is included in v2.1.2; the earlier v2.1.1 release remains unchanged.
