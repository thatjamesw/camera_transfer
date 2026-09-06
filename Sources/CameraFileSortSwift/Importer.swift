import AppKit
import Darwin
import Foundation

struct CameraScanner {
    static func detectCards(includePaths: [String]) -> [URL] {
        mountedRemovableVolumes().filter { url in
            for rel in includePaths {
                let candidate = url.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return true
                }
            }
            return false
        }
    }

    static func mountedRemovableVolumes() -> [URL] {
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.filter { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return false
            }
            return !shouldExcludeVolume(url)
        }
    }

    private static func shouldExcludeVolume(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.contains("macintosh hd") {
            return true
        }
        let keys: Set<URLResourceKey> = [
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        if values?.volumeIsInternal == true {
            return true
        }
        let removable = values?.volumeIsRemovable == true
        let ejectable = values?.volumeIsEjectable == true
        if !(removable || ejectable) {
            return true
        }
        return false
    }
}

private final class Locked<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

struct Importer {
    let settings: AppSettings
    let importDate: Date
    private let formatter: Locked<DateFormatter>

    init(settings: AppSettings, importDate: Date = Date()) {
        self.settings = settings
        self.importDate = importDate
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = settings.importDateFormat
        self.formatter = Locked(formatter)
    }

    private var primaryExtensions: Set<String> {
        Set((settings.photoExtensions + settings.videoExtensions).map { normalizedExtension($0) })
    }

    private var companionExtensions: Set<String> {
        Set([
            ".aae", ".bim", ".cpi", ".dop", ".lrf", ".lrv", ".mpl", ".pp3",
            ".rpp", ".srt", ".thm", ".wav", ".xmp", ".xml"
        ])
    }

    func scanSources(_ sources: [URL]) -> [SourceScan] {
        let scanCount = sources.count
        guard scanCount > 0 else { return [] }

        let results = (0..<scanCount).map { _ in Locked<SourceScan?>(nil) }
        DispatchQueue.concurrentPerform(iterations: scanCount) { index in
            let source = sources[index]
            var scanErrors: [String] = []
            let files = gatherFiles(in: source, extensions: settings.photoExtensions + settings.videoExtensions + Array(companionExtensions), errors: &scanErrors)
            let photoExtensions = Set(settings.photoExtensions.map { normalizedExtension($0) })
            let photoFiles = shouldInclude(.photo) ? files.filter { photoExtensions.contains($0.pathExtensionWithDot.lowercased()) } : []
            let videoExtensions = Set(settings.videoExtensions.map { normalizedExtension($0) })
            let videoFiles = shouldInclude(.video) ? files.filter { videoExtensions.contains($0.pathExtensionWithDot.lowercased()) && !photoExtensions.contains($0.pathExtensionWithDot.lowercased()) } : []
            let scan = SourceScan(
                source: source,
                photoFiles: photoFiles,
                videoFiles: videoFiles,
                hasDuplicates: false,
                errors: scanErrors,
                companionFiles: files.filter { companionExtensions.contains($0.pathExtensionWithDot.lowercased()) }
            )
            results[index].withLock { $0 = scan }
        }

        let scans = deduplicatedScans(results.compactMap { $0.withLock { $0 } })
        return scansWithImportDuplicateFlags(scans)
    }

    func transferFileCount(scans: [SourceScan]) -> Int {
        let photoDir = destinationDir(type: .photo)
        let videoDir = destinationDir(type: .video)
        return deduplicatedScans(scans).reduce(0) { count, scan in
            count + buildTransferEntries(for: scan, photoDir: photoDir, videoDir: videoDir).count
        }
    }

    func runImport(scans: [SourceScan], onProgress: ((ProgressUpdate) -> Void)? = nil) -> TransferResult {
        var result = TransferResult()
        if let error = settings.destinationConfigurationError {
            result.failed = 1
            result.transferFailures = [error]
            return result
        }
        let scanErrors = scans.flatMap(\.errors)
        if !scanErrors.isEmpty {
            result.failed = scanErrors.count
            result.transferFailures = scanErrors
            return result
        }
        do { try validatePaths(sources: scans.map(\.source)) } catch {
            result.failed = 1
            result.transferFailures = [error.localizedDescription]
            return result
        }
        let importScans = deduplicatedScans(scans)
        let photoDir = destinationDir(type: .photo)
        let videoDir = destinationDir(type: .video)
        let cardEntries = importScans.map { scan in
            buildTransferEntries(for: scan, photoDir: photoDir, videoDir: videoDir)
        }
        let totalPhoto = cardEntries.reduce(0) { count, entries in
            count + entries.filter { $0.type == .photo }.count
        }
        let totalVideo = cardEntries.reduce(0) { count, entries in
            count + entries.filter { $0.type == .video }.count
        }
        let totalFiles = totalPhoto + totalVideo
        if totalFiles == 0 {
            return result
        }

        let importState = ImportState()

        for (scan, cardFiles) in zip(importScans, cardEntries) {
            let cardName = scan.source.lastPathComponent
            processEntries(
                cardFiles,
                cardName: cardName,
                totalFiles: totalFiles,
                state: importState,
                onProgress: onProgress
            )
        }

        result = importState.snapshotResult()

        if settings.ejectAfter && result.failed == 0 {
            for target in ejectTargets(for: scans) {
                if let failure = eject(target: target) {
                    result.ejectFailures.append("\(target.displayName): \(failure)")
                }
            }
        }

        return result
    }

    private func gatherFiles(in source: URL, extensions: [String], errors: inout [String]) -> [URL] {
        let extSet = Set(extensions.map { normalizedExtension($0) })
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
              isDirectory.boolValue, FileManager.default.isReadableFile(atPath: source.path) else {
            errors.append("Cannot read source: " + source.path)
            return []
        }
        let failures = Locked<[String]>([])
        guard let enumerator = FileManager.default.enumerator(
            at: source.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                failures.withLock { $0.append(url.path + ": " + error.localizedDescription) }
                return true
            }
        ) else {
            errors.append("Cannot enumerate source: " + source.path)
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isRegularFile == true, values.isSymbolicLink != true,
                   extSet.contains(url.pathExtensionWithDot.lowercased()) {
                    files.append(url)
                }
            } catch {
                errors.append(url.path + ": " + error.localizedDescription)
            }
        }
        errors.append(contentsOf: failures.withLock { $0 })
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func deduplicatedScans(_ scans: [SourceScan]) -> [SourceScan] {
        var seenFiles = Set<String>()
        return scans.compactMap { scan in
            let photoFiles = uniqueMediaFiles(scan.photoFiles, seenFiles: &seenFiles)
            let videoFiles = uniqueMediaFiles(scan.videoFiles, seenFiles: &seenFiles)
            guard !photoFiles.isEmpty || !videoFiles.isEmpty || !scan.errors.isEmpty else {
                return nil
            }
            return SourceScan(
                source: scan.source,
                photoFiles: photoFiles,
                videoFiles: videoFiles,
                hasDuplicates: scan.hasDuplicates,
                errors: scan.errors,
                companionFiles: scan.companionFiles
            )
        }
    }

    private func uniqueMediaFiles(_ files: [URL], seenFiles: inout Set<String>) -> [URL] {
        files.filter { file in
            seenFiles.insert(mediaIdentity(for: file)).inserted
        }
    }

    private func mediaIdentity(for file: URL) -> String {
        var info = stat()
        let path = file.standardizedFileURL.path
        if stat(path, &info) == 0 {
            return "file:\(info.st_dev):\(info.st_ino)"
        }
        return "path:\(path)"
    }

    private func scansWithImportDuplicateFlags(_ scans: [SourceScan]) -> [SourceScan] {
        var seenTargets = Set<String>()

        return scans.map { scan in
            var hasDuplicates = scan.hasDuplicates
            for entry in buildTransferEntries(
                for: scan,
                photoDir: destinationDir(type: .photo),
                videoDir: destinationDir(type: .video)
            ) {
                let target = destinationDir(type: entry.type, fileURL: entry.dateReferenceFile, fallback: entry.fallbackDir)
                    .appendingPathComponent(entry.file.lastPathComponent)
                if (try? FileManager.default.attributesOfItem(atPath: target.path)) != nil || !seenTargets.insert(target.path.lowercased()).inserted {
                    hasDuplicates = true
                }
            }
            return SourceScan(
                source: scan.source,
                photoFiles: scan.photoFiles,
                videoFiles: scan.videoFiles,
                hasDuplicates: hasDuplicates,
                errors: scan.errors,
                companionFiles: scan.companionFiles
            )
        }
    }

    private func buildTransferEntries(for scan: SourceScan, photoDir: URL, videoDir: URL) -> [TransferEntry] {
        var entries: [TransferEntry] = []
        if shouldInclude(.photo) {
            entries.append(contentsOf: transferEntries(for: scan.photoFiles, fallbackDir: photoDir, type: .photo, availableCompanions: scan.companionFiles))
        }
        if shouldInclude(.video) {
            entries.append(contentsOf: transferEntries(for: scan.videoFiles, fallbackDir: videoDir, type: .video, availableCompanions: scan.companionFiles))
        }
        return deduplicatedTransferEntries(entries)
    }

    private func transferEntries(for files: [URL], fallbackDir: URL, type: MediaType, availableCompanions: [URL]?) -> [TransferEntry] {
        var companionsByDirectory: [URL: [String: [URL]]] = [:]
        let primaryExtensions = primaryExtensions
        let companionExtensions = companionExtensions
        let scannedByDirectory = availableCompanions.map { Dictionary(grouping: $0, by: { $0.deletingLastPathComponent() }) }
        for directory in Set(files.map { $0.deletingLastPathComponent() }) {
            let siblings = scannedByDirectory.map { $0[directory] ?? [] } ?? (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])) ?? []
            let companions = siblings.filter {
                let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                let ext = normalizedExtension($0.pathExtensionWithDot)
                return values?.isRegularFile == true && values?.isSymbolicLink != true && companionExtensions.contains(ext) && !primaryExtensions.contains(ext)
            }
            companionsByDirectory[directory] = Dictionary(grouping: companions, by: { $0.deletingPathExtension().lastPathComponent.lowercased() })
        }
        return files.flatMap { file in
            let primary = TransferEntry(file: file, dateReferenceFile: file, fallbackDir: fallbackDir, type: type)
            let companions = (companionsByDirectory[file.deletingLastPathComponent()]?[file.deletingPathExtension().lastPathComponent.lowercased()] ?? []).sorted { $0.path < $1.path }.map { companion in
                TransferEntry(file: companion, dateReferenceFile: file, fallbackDir: fallbackDir, type: type)
            }
            return [primary] + companions
        }
    }

    private func deduplicatedTransferEntries(_ entries: [TransferEntry]) -> [TransferEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            seen.insert(mediaIdentity(for: entry.file)).inserted
        }
    }

    private func processEntries(
        _ entries: [TransferEntry],
        cardName: String,
        totalFiles: Int,
        state: ImportState,
        onProgress: ((ProgressUpdate) -> Void)?
    ) {
        guard !entries.isEmpty else { return }

        state.beginCard(cardName)
        let keepBoth = settings.duplicatePolicy == .keepBoth ? keepBothTargets(for: entries) : ([:], 0)
        state.recordDuplicates(keepBoth.1)
        for entry in entries {
            autoreleasepool {
                let startedProgress = state.markStarted(
                    cardName: cardName,
                    fileName: entry.file.lastPathComponent,
                    cardTotal: entries.count,
                    totalFiles: totalFiles
                )
                onProgress?(startedProgress)

                let actualDestDir = destinationDir(type: entry.type, fileURL: entry.dateReferenceFile, fallback: entry.fallbackDir)
                let target = keepBoth.0[entry.file] ?? actualDestDir.appendingPathComponent(entry.file.lastPathComponent)
                let resolution = state.resolveDestination(
                    proposedTarget: target,
                    duplicatePolicy: settings.duplicatePolicy
                )

                switch resolution {
                case .skip:
                    let progress = state.markCompleted(cardName: cardName, fileName: entry.file.lastPathComponent, cardTotal: entries.count, totalFiles: totalFiles)
                    onProgress?(progress)
                case .transfer(let finalTarget):
                    let outcome = moveOrCopy(entry.file, to: finalTarget)
                    state.finishTransfer(
                        source: entry.file,
                        target: finalTarget,
                        outcome: outcome
                    )
                    let progress = state.markCompleted(cardName: cardName, fileName: entry.file.lastPathComponent, cardTotal: entries.count, totalFiles: totalFiles)
                    onProgress?(progress)
                }
            }
        }

    }

    private func keepBothTargets(for entries: [TransferEntry]) -> ([URL: URL], Int) {
        let groups = Dictionary(grouping: entries, by: \.dateReferenceFile)
        var seen = Set<URL>()
        var reserved = Set<String>()
        var targets: [URL: URL] = [:]
        var duplicateCount = 0
        // Use source order so the result is stable across imports.
        for entry in entries where seen.insert(entry.dateReferenceFile).inserted {
            let group = groups[entry.dateReferenceFile] ?? []
            var suffix = 0
            while true {
                let candidates = group.map { member -> URL in
                    let directory = destinationDir(type: member.type, fileURL: member.dateReferenceFile, fallback: member.fallbackDir)
                    let base = member.file.deletingPathExtension().lastPathComponent
                    let name = suffix == 0 ? base : "\(base)_\(suffix)"
                    return directory.appendingPathComponent(name).appendingPathExtension(member.file.pathExtension)
                }
                let collisions = candidates.filter {
                    reserved.contains($0.path.lowercased()) ||
                    (try? FileManager.default.attributesOfItem(atPath: $0.path)) != nil
                }.count
                if suffix == 0 { duplicateCount += collisions }
                if collisions == 0 {
                    for (member, target) in zip(group, candidates) {
                        targets[member.file] = target
                        reserved.insert(target.path.lowercased())
                    }
                    break
                }
                suffix += 1
            }
        }
        return (targets, duplicateCount)
    }

    private func moveOrCopy(_ file: URL, to target: URL) -> TransferOutcome {
        do {
            try validateOutput(target)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch { return .failure(error.localizedDescription) }
        let writingOptions: NSFileCoordinator.WritingOptions =
            FileManager.default.fileExists(atPath: target.path) ? .forReplacing : []
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: TransferOutcome = .failure("File coordination did not complete.")
        if settings.action == .move {
            coordinator.coordinate(writingItemAt: file, options: .forDeleting,
                                   writingItemAt: target, options: writingOptions,
                                   error: &coordinationError) { source, destination in
                outcome = transferCoordinated(source, to: destination)
            }
        } else {
            coordinator.coordinate(readingItemAt: file, options: [],
                                   writingItemAt: target, options: writingOptions,
                                   error: &coordinationError) { source, destination in
                outcome = transferCoordinated(source, to: destination)
            }
        }
        return coordinationError.map { .failure($0.localizedDescription) } ?? outcome
    }

    private func transferCoordinated(_ file: URL, to target: URL) -> TransferOutcome {
        let fm = FileManager.default
        let staging = target.deletingLastPathComponent().appendingPathComponent(".camera-transfer-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        do {
            try validateOutput(target)
            let source = file.resolvingSymlinksInPath().standardizedFileURL
            guard source != target.resolvingSymlinksInPath().standardizedFileURL else {
                throw importError("Source and destination refer to the same file.")
            }
            let attributes = try fm.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw importError("Source is no longer a regular file.")
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: staging)
            let copiedAttributes = try fm.attributesOfItem(atPath: staging.path)
            let currentAttributes = try fm.attributesOfItem(atPath: file.path)
            guard attributes[.size] as? NSNumber == copiedAttributes[.size] as? NSNumber,
                  attributes[.size] as? NSNumber == currentAttributes[.size] as? NSNumber,
                  attributes[.modificationDate] as? Date == currentAttributes[.modificationDate] as? Date else {
                throw importError("Source changed during transfer. Original retained.")
            }
            // Commit on the destination filesystem; non-overwrite must never replace a late arrival.
            try validateOutput(target)
            if settings.duplicatePolicy == .overwrite && fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: staging, options: [.usingNewMetadataOnly])
            } else {
                try fm.moveItem(at: staging, to: target)
            }
            if settings.action == .move { try fm.removeItem(at: file) }
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func importError(_ message: String) -> NSError {
        NSError(domain: "CameraFileSortSwift.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func validatePaths(sources: [URL]) throws {
        let target = settings.targetRoot.resolvingSymlinksInPath().standardizedFileURL.path
        for sourceURL in sources {
            let source = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
            if source == "/" || target == source || target.hasPrefix(source + "/") || source.hasPrefix(target + "/") {
                throw importError("Source and destination folders must not overlap.")
            }
        }
        try validateOutput(settings.targetRoot.appendingPathComponent("placeholder"))
    }

    private func validateOutput(_ target: URL) throws {
        let configured = URL(fileURLWithPath: (settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath)
        let components = configured.pathComponents
        if components.count > 2, components[1] == "Volumes",
           !FileManager.default.fileExists(atPath: "/Volumes/" + components[2]) {
            throw importError("Destination volume is not mounted.")
        }
        let base = configured
            .resolvingSymlinksInPath().standardizedFileURL
        let lexicalRoot = base.appendingPathComponent(settings.selectedDevice.folderName).standardizedFileURL
        let actualRoot = lexicalRoot.resolvingSymlinksInPath().standardizedFileURL
        guard actualRoot == lexicalRoot else { throw importError("The device folder must not be a symbolic link.") }
        let resolved = target.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.hasPrefix(actualRoot.path + "/") else {
            throw importError("Destination leaves the selected device folder.")
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: target.path),
           attributes[.type] as? FileAttributeType != .typeRegular {
            throw importError("Destination is not a regular file.")
        }
    }

    private func mountedVolumeRoot(for source: URL) -> URL? {
        let standardizedPath = source.standardizedFileURL.path
        let components = NSString(string: standardizedPath).pathComponents
        guard components.count >= 3, components[0] == "/", components[1] == "Volumes" else {
            return nil
        }
        let volumePath = NSString.path(withComponents: Array(components.prefix(3)))
        return URL(fileURLWithPath: volumePath, isDirectory: true)
    }

    private func destinationDir(type: MediaType) -> URL {
        return destinationDir(type: type, fileURL: nil)
    }

    private func destinationDir(type: MediaType, fileURL: URL?, fallback: URL? = nil) -> URL {
        let root = settings.targetRoot
        let folderName = destinationFolderName(for: type)
        if settings.dateSource == .none {
            return root.appendingPathComponent(folderName)
        }
        let dateString = dateStringFor(fileURL: fileURL)
        if let dateString {
            return root.appendingPathComponent(folderName).appendingPathComponent(dateString)
        }
        if let fallback {
            return fallback
        }
        let date = formatter.withLock { $0.string(from: importDate) }
        return root.appendingPathComponent(folderName).appendingPathComponent(date)
    }

    private func dateStringFor(fileURL: URL?) -> String? {
        switch settings.dateSource {
        case .importDate:
            return formatter.withLock { $0.string(from: importDate) }
        case .fileDate:
            guard let fileURL else { return nil }
            let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            guard let date = values?.creationDate ?? values?.contentModificationDate else { return nil }
            return formatter.withLock { $0.string(from: date) }
        case .none:
            return nil
        }
    }

    private func normalizedExtension(_ ext: String) -> String {
        let trimmed = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"
    }

    private func shouldInclude(_ type: MediaType) -> Bool {
        switch settings.mediaSelection {
        case .photo:
            return type == .photo
        case .video:
            return type == .video
        case .both:
            return type == .photo || type == .video
        }
    }

    private func destinationFolderName(for type: MediaType) -> String {
        switch settings.destinationMode {
        case .separate:
            return type.rawValue
        case .same:
            return settings.sameFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "media"
                : settings.sameFolderName
        case .custom:
            if type == .photo {
                return settings.photoFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "photo"
                    : settings.photoFolderName
            }
            return settings.videoFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "video"
                : settings.videoFolderName
        }
    }

    private func ensureVolumeIsEjectable(_ volume: URL) throws {
        let values = try volume.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey])
        if values.volumeIsInternal == true {
            throw NSError(domain: "CameraFileSortSwift.Eject", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "This volume is internal and cannot be ejected."
            ])
        }
        let canEject = values.volumeIsRemovable == true || values.volumeIsEjectable == true
        if !canEject {
            throw NSError(domain: "CameraFileSortSwift.Eject", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "This volume cannot be safely ejected."
            ])
        }
    }

    private func ejectTargets(for scans: [SourceScan]) -> [EjectTarget] {
        let selectedVolumes = scans.compactMap { mountedVolumeRoot(for: $0.source) }
        guard !selectedVolumes.isEmpty else { return [] }

        let mountedVolumes = CameraScanner.mountedRemovableVolumes()
        var groupedVolumes: [String: [URL]] = [:]
        var metadataByPath: [String: DiskMetadata] = [:]
        for volume in mountedVolumes {
            guard let metadata = diskMetadata(for: volume) else { continue }
            metadataByPath[volume.path] = metadata
            groupedVolumes[metadata.wholeDiskIdentifier, default: []].append(volume)
        }

        let selectedMetadata = selectedVolumes.compactMap { metadataByPath[$0.path] ?? diskMetadata(for: $0) }
        let selectedGroupingKeys = Set(selectedMetadata.flatMap(\.cameraGroupingKeys))
        let selectedWholeDisks = Set(selectedMetadata.map(\.wholeDiskIdentifier))
        let companionVolumes = mountedVolumes.filter { volume in
            guard !selectedVolumes.contains(where: { $0.path == volume.path }) else { return false }
            guard looksLikeCameraCompanionVolume(volume) else { return false }
            guard let metadata = metadataByPath[volume.path] else { return false }
            if selectedWholeDisks.contains(metadata.wholeDiskIdentifier) {
                return true
            }
            return !selectedGroupingKeys.isDisjoint(with: metadata.cameraGroupingKeys)
        }
        let volumesToEject = selectedVolumes + companionVolumes

        var seenIdentifiers = Set<String>()
        var targets: [EjectTarget] = []
        for volume in volumesToEject {
            if let metadata = metadataByPath[volume.path] ?? diskMetadata(for: volume) {
                guard seenIdentifiers.insert(metadata.wholeDiskIdentifier).inserted else { continue }
                let siblingVolumes = groupedVolumes[metadata.wholeDiskIdentifier] ?? [volume]
                targets.append(.wholeDisk(identifier: metadata.wholeDiskIdentifier, volumes: siblingVolumes.sorted { $0.path < $1.path }))
                continue
            }

            guard seenIdentifiers.insert(volume.path).inserted else { continue }
            targets.append(.volume(volume))
        }

        return targets
    }

    private func looksLikeCameraCompanionVolume(_ volume: URL) -> Bool {
        if volume.lastPathComponent.caseInsensitiveCompare("PMHOME") == .orderedSame {
            return true
        }
        for rel in settings.includePaths {
            if FileManager.default.fileExists(atPath: volume.appendingPathComponent(rel).path) {
                return true
            }
        }
        return false
    }

    private func eject(target: EjectTarget) -> String? {
        switch target {
        case .wholeDisk(let identifier, let volumes):
            guard volumes.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                return nil
            }
            do {
                for volume in volumes {
                    try ensureVolumeIsEjectable(volume)
                    let output = settings.targetRoot.resolvingSymlinksInPath().path
                    if output == volume.path || output.hasPrefix(volume.path + "/") {
                        throw importError("The destination is on this device; left mounted.")
                    }
                }
                try ejectWholeDisk(identifier)
                return nil
            } catch {
                return error.localizedDescription
            }
        case .volume(let volume):
            guard FileManager.default.fileExists(atPath: volume.path) else { return nil }
            do {
                try ensureVolumeIsEjectable(volume)
                let output = settings.targetRoot.resolvingSymlinksInPath().path
                guard !output.hasPrefix(volume.path + "/") else { throw importError("The destination is on this device; left mounted.") }
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    private func diskMetadata(for volume: URL) -> DiskMetadata? {
        guard let info = diskInfo(for: volume) else {
            return nil
        }
        guard let wholeDiskIdentifier = wholeDiskIdentifier(from: info) else {
            return nil
        }
        return DiskMetadata(
            wholeDiskIdentifier: wholeDiskIdentifier,
            cameraGroupingKeys: cameraGroupingKeys(from: info)
        )
    }

    private func wholeDiskIdentifier(from info: [String: Any]) -> String? {
        if let wholeDisk = info["ParentWholeDisk"] as? String, !wholeDisk.isEmpty {
            return wholeDisk
        }
        if let wholeDisk = info["PartOfWhole"] as? String, !wholeDisk.isEmpty {
            return wholeDisk
        }
        if info["WholeDisk"] as? Bool == true, let deviceIdentifier = info["DeviceIdentifier"] as? String, !deviceIdentifier.isEmpty {
            return deviceIdentifier
        }
        return nil
    }

    private func cameraGroupingKeys(from info: [String: Any]) -> Set<String> {
        let keyNames = ["DeviceTreePath"]
        return Set(keyNames.compactMap { key in
            guard let value = info[key] else { return nil }
            if let stringValue = value as? String, !stringValue.isEmpty {
                return "\(key)=\(stringValue)"
            }
            if let boolValue = value as? Bool {
                return "\(key)=\(boolValue)"
            }
            return nil
        })
    }

    private func diskInfo(for volume: URL) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", volume.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeout)
        defer { timeout.cancel() }
        let outputData: Data
        do {
            try process.run()
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: outputData, options: [], format: nil),
              let info = plist as? [String: Any] else {
            return nil
        }
        return info
    }

    private func ejectWholeDisk(_ identifier: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", identifier]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeout)
        defer { timeout.cancel() }

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "CameraFileSortSwift.Eject", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "diskutil failed to eject the device."
            ])
        }
    }
}

private enum EjectTarget {
    case wholeDisk(identifier: String, volumes: [URL])
    case volume(URL)

    var displayName: String {
        switch self {
        case .wholeDisk(_, let volumes):
            let names = volumes.map(\.lastPathComponent).sorted()
            return names.joined(separator: ", ")
        case .volume(let volume):
            return volume.lastPathComponent
        }
    }
}

private struct DiskMetadata {
    let wholeDiskIdentifier: String
    let cameraGroupingKeys: Set<String>
}

struct SourceScan {
    let source: URL
    let photoFiles: [URL]
    let videoFiles: [URL]
    let hasDuplicates: Bool
    var errors: [String] = []
    var companionFiles: [URL]? = nil
}

struct ProgressUpdate {
    let currentCard: String
    let currentFile: String
    let cardProgress: Double
    let overallProgress: Double
    let overallIndex: Int
}

enum MediaType: String {
    case photo
    case video
}

private extension URL {
    var pathExtensionWithDot: String {
        let ext = pathExtension
        if ext.isEmpty { return "" }
        return ".\(ext)"
    }
}

private struct TransferEntry {
    let file: URL
    let dateReferenceFile: URL
    let fallbackDir: URL
    let type: MediaType
}

private enum DestinationResolution {
    case skip
    case transfer(URL)
}

private enum TransferOutcome {
    case success
    case failure(String)
}

// Transfers are deliberately serial: bounded memory and predictable writes to camera cards.
private final class ImportState {
    private var result = TransferResult()
    private var overallCompleted = 0
    private var cardCompleted: [String: Int] = [:]

    func resolveDestination(proposedTarget: URL, duplicatePolicy: DuplicatePolicy) -> DestinationResolution {
        let attributes = try? FileManager.default.attributesOfItem(atPath: proposedTarget.path)
        guard attributes != nil else { return .transfer(proposedTarget) }
        result.duplicates += 1
        switch duplicatePolicy {
        case .skip, .prompt:
            result.skipped += 1
            return .skip
        case .keepBoth:
            return .transfer(uniqueDestination(for: proposedTarget))
        case .overwrite:
            return .transfer(proposedTarget)
        }
    }

    func finishTransfer(source: URL, target: URL, outcome: TransferOutcome) {
        switch outcome {
        case .success:
            result.copied += 1
        case .failure(let message):
            result.failed += 1
            result.transferFailures.append("\(source.lastPathComponent) -> \(target.path): \(message)")
        }
    }

    func recordDuplicates(_ count: Int) { result.duplicates += count }

    func beginCard(_ name: String) { cardCompleted[name] = 0 }

    func markStarted(cardName: String, fileName: String, cardTotal: Int, totalFiles: Int) -> ProgressUpdate {
        ProgressUpdate(
            currentCard: cardName, currentFile: fileName,
            cardProgress: progressValue(index: cardCompleted[cardName, default: 0], total: cardTotal),
            overallProgress: progressValue(index: overallCompleted, total: totalFiles),
            overallIndex: overallCompleted
        )
    }

    func markCompleted(cardName: String, fileName: String, cardTotal: Int, totalFiles: Int) -> ProgressUpdate {
        overallCompleted += 1
        cardCompleted[cardName, default: 0] += 1
        return markStarted(cardName: cardName, fileName: fileName, cardTotal: cardTotal, totalFiles: totalFiles)
    }

    func snapshotResult() -> TransferResult { result }

    private func uniqueDestination(for target: URL) -> URL {
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var counter = 1
        while true {
            let candidate = target.deletingLastPathComponent()
                .appendingPathComponent("\(base)_\(counter)")
                .appendingPathExtension(ext)
            if (try? FileManager.default.attributesOfItem(atPath: candidate.path)) == nil {
                return candidate
            }
            counter += 1
        }
    }
}

private func progressValue(index: Int, total: Int) -> Double {
    guard total > 0 else { return 0 }
    return Double(index) / Double(total)
}
