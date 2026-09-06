import Foundation

@main
struct RegressionChecks {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func write(_ path: String, _ text: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            return url
        }
        var settings = AppSettings.default
        settings.destinationRoot = root.appendingPathComponent("kuva/import").path
        settings.ejectAfter = false
        settings.dateSource = .none
        settings.duplicatePolicy = .skip
        let photo = try write("card1/A.JPG", "photo")
        _ = try write("card1/A.XMP", "sidecar")
        _ = try write("card2/B.MP4", "video")
        try fm.createDirectory(at: root.appendingPathComponent("card1/fake.JPG"), withIntermediateDirectories: true)
        let sources = ["card1", "card2"].map { root.appendingPathComponent($0) }
        for target in ImportTarget.allCases {
            settings.selectedTarget = target
            let importer = Importer(settings: settings)
            let scans = importer.scanSources(sources)
            precondition(scans.count == 2, "Both card results must survive")
            precondition(scans.reduce(0) { $0 + $1.photoFiles.count } == 1)
            precondition(importer.transferFileCount(scans: scans) == 3)
            let result = importer.runImport(scans: scans)
            precondition(result.copied == 3 && result.failed == 0, String(describing: result))
            precondition(fm.fileExists(atPath: settings.targetRoot.appendingPathComponent("photo/A.JPG").path))
            precondition(fm.fileExists(atPath: settings.targetRoot.appendingPathComponent("video/B.MP4").path))
            precondition(importer.runImport(scans: importer.scanSources(sources)).skipped == 3)
        }
        settings.duplicatePolicy = .keepBoth
        var importer = Importer(settings: settings)
        precondition(importer.runImport(scans: importer.scanSources(sources)).copied == 3)
        precondition(fm.fileExists(atPath: settings.targetRoot.appendingPathComponent("photo/A_1.JPG").path))
        settings.duplicatePolicy = .overwrite
        importer = Importer(settings: settings)
        try Data("replacement".utf8).write(to: photo)
        precondition(importer.runImport(scans: importer.scanSources(sources)).failed == 0)
        let destination = settings.targetRoot.appendingPathComponent("photo/A.JPG")
        let replaced = try String(contentsOf: destination, encoding: .utf8)
        precondition(replaced == "replacement")
        let stale = importer.scanSources(sources)
        try fm.removeItem(at: photo)
        let failed = importer.runImport(scans: stale)
        precondition(failed.failed == 1)
        let preserved = try String(contentsOf: destination, encoding: .utf8)
        precondition(preserved == "replacement", "Failed overwrite must preserve existing file")
        let encoded = try JSONEncoder().encode(AppSettings.default)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        precondition(decoded.selectedTarget == .misc)
        settings.selectedTarget = .sonyA1II
        settings.destinationMode = .same
        settings.sameFolderName = "all"
        settings.dateSource = .importDate
        settings.importDateFormat = "yyyy-MM-dd"
        importer = Importer(settings: settings)
        let result = importer.runImport(scans: importer.scanSources([sources[1]]))
        precondition(result.copied == 1 && result.failed == 0)
        // Missing sources must be an explicit failure, never a successful empty import.
        var audit = AppSettings.default
        audit.destinationRoot = root.appendingPathComponent("audit").path
        audit.dateSource = .none
        audit.ejectAfter = false
        audit.duplicatePolicy = .overwrite
        var auditImporter = Importer(settings: audit)
        let missing = auditImporter.scanSources([root.appendingPathComponent("missing-card")])
        precondition(missing.flatMap(\.errors).count == 1)
        precondition(auditImporter.runImport(scans: missing).failed == 1)

        // Custom paths cannot escape the device root.
        audit.destinationMode = .custom
        audit.photoFolderName = "../escaped"
        precondition(audit.destinationConfigurationError != nil)
        auditImporter = Importer(settings: audit)
        precondition(auditImporter.runImport(scans: auditImporter.scanSources([sources[1]])).failed == 1)
        audit.destinationMode = .separate
        audit.photoFolderName = "photo"
        audit.dateSource = .importDate
        audit.importDateFormat = "../../yyyy"
        precondition(audit.destinationConfigurationError != nil)
        audit.dateSource = .none

        // Reject device-folder symlinks without writing through them.
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createDirectory(at: URL(fileURLWithPath: audit.destinationRoot), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: audit.targetRoot, withDestinationURL: outside)
        auditImporter = Importer(settings: audit)
        precondition(auditImporter.runImport(scans: auditImporter.scanSources([sources[1]])).failed == 1)
        let outsideContents = try fm.contentsOfDirectory(atPath: outside.path)
        precondition(outsideContents.isEmpty)
        try fm.removeItem(at: audit.targetRoot)

        // Guard overlap in the engine, including callers that bypass AppState.
        audit.destinationRoot = sources[1].path
        auditImporter = Importer(settings: audit)
        precondition(auditImporter.runImport(scans: auditImporter.scanSources([sources[1]])).failed == 1)

        // Old metadata-only manifests must not suppress a missing destination.
        audit.destinationRoot = root.appendingPathComponent("history").path
        audit.duplicatePolicy = .skip
        try fm.createDirectory(at: audit.targetRoot, withIntermediateDirectories: true)
        try Data("[\"B.MP4|5|0\"]".utf8).write(to: audit.targetRoot.appendingPathComponent(".camera_transfer_manifest.json"))
        auditImporter = Importer(settings: audit)
        precondition(auditImporter.runImport(scans: auditImporter.scanSources([sources[1]])).copied == 1)

        // Separate sources sharing a display name must each finish at 100%.
        _ = try write("one/CARD/ONE.JPG", "one")
        _ = try write("two/CARD/TWO.JPG", "two")
        let sameNames = ["one/CARD", "two/CARD"].map { root.appendingPathComponent($0) }
        var progress: [Double] = []
        let scan = auditImporter.scanSources(sameNames)
        let auditResult = auditImporter.runImport(scans: scan) { progress.append($0.cardProgress) }
        precondition(auditResult.copied == 2 && progress.allSatisfy { $0 >= 0 && $0 <= 1 })

        // Moving only removes source after committing a complete destination.
        let moving = try write("move/C.JPG", "move me")
        audit.action = .move
        auditImporter = Importer(settings: audit)
        let moved = auditImporter.runImport(scans: auditImporter.scanSources([moving.deletingLastPathComponent()]))
        precondition(moved.copied == 1 && moved.failed == 0)
        precondition(!fm.fileExists(atPath: moving.path))
        precondition(fm.fileExists(atPath: audit.targetRoot.appendingPathComponent("photo/C.JPG").path))

        // Keep-both must retain the same suffix for a photo and its sidecar.
        let paired = try write("paired/D.JPG", "new photo")
        _ = try write("paired/D.XMP", "metadata")
        try Data("old photo".utf8).write(to: audit.targetRoot.appendingPathComponent("photo/D.JPG"))
        audit.action = .copy
        audit.duplicatePolicy = .keepBoth
        auditImporter = Importer(settings: audit)
        let pairedResult = auditImporter.runImport(scans: auditImporter.scanSources([paired.deletingLastPathComponent()]))
        precondition(pairedResult.copied == 2 && pairedResult.duplicates == 1)
        precondition(fm.fileExists(atPath: audit.targetRoot.appendingPathComponent("photo/D_1.JPG").path))
        precondition(fm.fileExists(atPath: audit.targetRoot.appendingPathComponent("photo/D_1.XMP").path))

        var managed = AppSettings.default
        managed.selectedTarget = .djiAvata2
        precondition(managed.selectedDevice.name == "DJI Avata 2")
        precondition(managed.addDevice(named: "  Nikon Z8  ") == nil)
        let newID = managed.activeDeviceID
        precondition(managed.selectedDevice.name == "Nikon Z8")
        precondition(managed.addDevice(named: "nikon z8") != nil)
        precondition(managed.addDevice(named: "NikonZ8") != nil)
        precondition(ImportDevice(id: "test", name: "Sony A1 II").folderName == "SonyA1II")
        precondition(managed.addDevice(named: "../escape") != nil)
        precondition(managed.renameDevice(newID, to: "Nikon Z9") == nil)
        precondition(managed.activeDeviceID == newID)
        precondition(managed.targetRoot.lastPathComponent == "NikonZ9")
        managed = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(managed))
        precondition(managed.selectedDevice.name == "Nikon Z9")
        managed.removeDevice(newID)
        precondition(managed.activeDeviceID != newID)
        for device in managed.availableDevices { managed.removeDevice(device.id) }
        precondition(managed.availableDevices.count == 1)
        precondition(!managed.selectedDevice.name.isEmpty)
        var oldSettings = AppSettings.default
        oldSettings.destinationRoot = "/temporary/last-used"
        UserDefaults.standard.setVolatileDomain([
            "CameraFileSortSwift.Settings": try JSONEncoder().encode(oldSettings),
            "CameraFileSortSwift.DefaultRoot": root.path
        ], forName: UserDefaults.argumentDomain)
        let state = AppState()
        precondition(state.settings.destinationRoot == root.path, "Saved default wins at launch")
        UserDefaults.standard.setVolatileDomain([
            "CameraFileSortSwift.Settings": try JSONEncoder().encode(oldSettings)
        ], forName: UserDefaults.argumentDomain)
        // Explicit empty default masks any real user preference without modifying it.
        UserDefaults.standard.setVolatileDomain([
            "CameraFileSortSwift.Settings": try JSONEncoder().encode(oldSettings),
            "CameraFileSortSwift.DefaultRoot": ""
        ], forName: UserDefaults.argumentDomain)
        precondition(AppState().settings.destinationRoot.isEmpty)
        // Duplicate choice must keep the import locked until completion.
        var promptSettings = audit
        promptSettings.action = .copy
        promptSettings.duplicatePolicy = .prompt
        UserDefaults.standard.setVolatileDomain([
            "CameraFileSortSwift.Settings": try JSONEncoder().encode(promptSettings),
            "CameraFileSortSwift.DefaultRoot": promptSettings.destinationRoot
        ], forName: UserDefaults.argumentDomain)
        let promptState = AppState()
        promptState.selectedCards = Set([sources[1]])
        promptState.startImport()
        for _ in 0..<200 {
            if promptState.alert != nil { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        precondition(promptState.alert?.buttons.count == 3)
        precondition(promptState.isImporting)
        promptState.alert?.onSelect?(.skip)
        precondition(promptState.isImporting, "Choosing a policy must not unlock the import")
        for _ in 0..<200 {
            if !promptState.isImporting { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        precondition(!promptState.isImporting && !promptState.importHadErrors)
        precondition(promptState.processedCount == promptState.totalCount)

        if CommandLine.arguments.contains("--performance") {
            let benchmarkSource = root.appendingPathComponent("benchmark/source")
            try fm.createDirectory(at: benchmarkSource, withIntermediateDirectories: true)
            let small = Data(repeating: 65, count: 4096)
            let large = Data(repeating: 66, count: 1024 * 1024)
            for index in 0..<1000 {
                try small.write(to: benchmarkSource.appendingPathComponent("PHOTO_\(index).JPG"))
                try small.write(to: benchmarkSource.appendingPathComponent("PHOTO_\(index).XMP"))
            }
            for index in 0..<50 {
                try large.write(to: benchmarkSource.appendingPathComponent("VIDEO_\(index).MP4"))
            }
            var benchmarkSettings = AppSettings.default
            benchmarkSettings.destinationRoot = root.appendingPathComponent("benchmark/output").path
            benchmarkSettings.ejectAfter = false
            benchmarkSettings.dateSource = .none
            let benchmark = Importer(settings: benchmarkSettings)
            let scanStart = Date()
            let scans = benchmark.scanSources([benchmarkSource])
            let scanSeconds = Date().timeIntervalSince(scanStart)
            let copyStart = Date()
            let copied = benchmark.runImport(scans: scans)
            let copySeconds = Date().timeIntervalSince(copyStart)
            precondition(copied.copied == 2050 && copied.failed == 0)
            print(String(format: "Synthetic APFS benchmark: 2,050 files (1,000 photos, 1,000 sidecars, 50 videos); scan %.3fs; copy %.3fs.", scanSeconds, copySeconds))
        }
        print("Passed: path containment, symlinks, missing sources, stale manifests, same-name progress, move commit, device management, saved default restoration, empty default,  all targets, multi-card scans, regular files, sidecars, manifests, skip, keep-both, overwrite, failed overwrite preservation, legacy decoding, shared/date layout.")
    }
}
