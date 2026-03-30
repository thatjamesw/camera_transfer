import AppKit
import Foundation

struct CameraScanner {
    static func detectCards(includePaths: [String]) -> [URL] {
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.filter { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return false
            }
            if shouldExcludeVolume(url) {
                return false
            }
            for rel in includePaths {
                let candidate = url.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return true
                }
            }
            return false
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

    func scanSources(_ sources: [URL]) -> [SourceScan] {
        let knownSignatures = loadManifest()
        let scanCount = sources.count
        guard scanCount > 0 else { return [] }

        let results = Array(repeating: Locked<SourceScan?>(nil), count: scanCount)
        DispatchQueue.concurrentPerform(iterations: scanCount) { index in
            let source = sources[index]
            let photoFiles = shouldInclude(.photo) ? gatherFiles(in: source, extensions: settings.photoExtensions) : []
            let videoFiles = shouldInclude(.video) ? gatherFiles(in: source, extensions: settings.videoExtensions) : []
            let photoHasDup = shouldInclude(.photo) && hasDuplicatesForFiles(files: photoFiles, type: .photo, knownSignatures: knownSignatures)
            let videoHasDup = shouldInclude(.video) && hasDuplicatesForFiles(files: videoFiles, type: .video, knownSignatures: knownSignatures)
            let scan = SourceScan(
                source: source,
                photoFiles: photoFiles,
                videoFiles: videoFiles,
                hasDuplicates: photoHasDup || videoHasDup
            )
            results[index].withLock { $0 = scan }
        }

        return results.compactMap { $0.withLock { $0 } }
    }

    func runImport(
        from sources: [URL],
        scans: [SourceScan],
        onProgress: ((ProgressUpdate) -> Void)? = nil
    ) -> TransferResult {
        var result = TransferResult()
        let totalPhoto = scans.reduce(0) { $0 + $1.photoFiles.count }
        let totalVideo = scans.reduce(0) { $0 + $1.videoFiles.count }
        let totalFiles = totalPhoto + totalVideo
        if totalFiles == 0 {
            return result
        }

        let photoDir = destinationDir(type: .photo)
        let videoDir = destinationDir(type: .video)
        if totalPhoto > 0 { createDirectory(photoDir) }
        if totalVideo > 0 { createDirectory(videoDir) }
        let importState = ImportState(
            knownSignatures: loadManifest(),
            maxConcurrentTransfers: recommendedTransferConcurrency()
        )

        for scan in scans {
            let cardFiles = buildTransferEntries(for: scan, photoDir: photoDir, videoDir: videoDir)
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

        if result.copied > 0 {
            saveManifest(importState.snapshotKnownSignatures())
        }

        if settings.ejectAfter {
            var seenVolumePaths = Set<String>()
            for scan in scans {
                guard let volume = mountedVolumeRoot(for: scan.source) else { continue }
                guard seenVolumePaths.insert(volume.path).inserted else { continue }
                if let failure = eject(volume: volume) {
                    result.ejectFailures.append("\(volume.lastPathComponent): \(failure)")
                }
            }
        }

        return result
    }

    private func gatherFiles(in source: URL, extensions: [String]) -> [URL] {
        let extSet = Set(extensions.map { $0.lowercased() })
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if extSet.contains(url.pathExtensionWithDot.lowercased()) {
                files.append(url)
            }
        }
        return files
    }

    private func hasDuplicatesForFiles(files: [URL], type: MediaType, knownSignatures: Set<String>) -> Bool {
        for file in files {
            let destDir = destinationDir(type: type, fileURL: file)
            let target = destDir.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                return true
            }
            if let signature = fileSignature(for: file), knownSignatures.contains(signature) {
                return true
            }
        }
        return false
    }

    private func buildTransferEntries(for scan: SourceScan, photoDir: URL, videoDir: URL) -> [TransferEntry] {
        var entries: [TransferEntry] = []
        if shouldInclude(.photo) {
            entries.append(contentsOf: scan.photoFiles.map { file in
                TransferEntry(file: file, fallbackDir: photoDir, type: .photo)
            })
        }
        if shouldInclude(.video) {
            entries.append(contentsOf: scan.videoFiles.map { file in
                TransferEntry(file: file, fallbackDir: videoDir, type: .video)
            })
        }
        return entries
    }

    private func processEntries(
        _ entries: [TransferEntry],
        cardName: String,
        totalFiles: Int,
        state: ImportState,
        onProgress: ((ProgressUpdate) -> Void)?
    ) {
        guard !entries.isEmpty else { return }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = state.maxConcurrentTransfers
        queue.qualityOfService = .userInitiated

        for entry in entries {
            queue.addOperation {
                let actualDestDir = destinationDir(type: entry.type, fileURL: entry.file, fallback: entry.fallbackDir)
                createDirectory(actualDestDir)
                let target = actualDestDir.appendingPathComponent(entry.file.lastPathComponent)
                let signature = fileSignature(for: entry.file)
                let resolution = state.resolveDestination(
                    source: entry.file,
                    proposedTarget: target,
                    signature: signature,
                    duplicatePolicy: settings.duplicatePolicy
                )

                switch resolution {
                case .skip:
                    let progress = state.markCompleted(cardName: cardName, fileName: entry.file.lastPathComponent, cardTotal: entries.count, totalFiles: totalFiles)
                    onProgress?(progress)
                case .transfer(let finalTarget, let signatureToTrack):
                    let didCopy = moveOrCopy(entry.file, to: finalTarget)
                    state.finishTransfer(
                        target: finalTarget,
                        signature: signatureToTrack,
                        succeeded: didCopy
                    )
                    let progress = state.markCompleted(cardName: cardName, fileName: entry.file.lastPathComponent, cardTotal: entries.count, totalFiles: totalFiles)
                    onProgress?(progress)
                }
            }
        }

        queue.waitUntilAllOperationsAreFinished()
    }

    private func moveOrCopy(_ file: URL, to target: URL) -> Bool {
        do {
            if settings.action == .move {
                try FileManager.default.moveItem(at: file, to: target)
            } else {
                try FileManager.default.copyItem(at: file, to: target)
            }
            return true
        } catch {
            return false
        }
    }

    private func fileSignature(for file: URL) -> String? {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        guard let values = try? file.resourceValues(forKeys: keys) else {
            return nil
        }
        guard let size = values.fileSize else {
            return nil
        }
        let timestamp = values.creationDate ?? values.contentModificationDate ?? Date.distantPast
        let epoch = Int64(timestamp.timeIntervalSince1970)
        return "\(file.lastPathComponent.lowercased())|\(size)|\(epoch)"
    }

    private func loadManifest() -> Set<String> {
        let url = manifestURL()
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        if let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return Set(decoded)
        }
        return []
    }

    private func saveManifest(_ signatures: Set<String>) {
        let url = manifestURL()
        createDirectory(url.deletingLastPathComponent())
        let sorted = signatures.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func manifestURL() -> URL {
        URL(fileURLWithPath: settings.destinationRoot)
            .appendingPathComponent(".camera_transfer_manifest.json")
    }

    private func uniqueDestination(for target: URL) -> URL {
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var counter = 1
        while true {
            let candidate = target.deletingLastPathComponent()
                .appendingPathComponent("\(base)_\(counter)")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    private func createDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func eject(volume: URL) -> String? {
        guard FileManager.default.fileExists(atPath: volume.path) else { return nil }
        do {
            try ensureVolumeIsEjectable(volume)
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            return nil
        } catch {
            return error.localizedDescription
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
        let root = URL(fileURLWithPath: settings.destinationRoot)
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
        let formatter = DateFormatter()
        formatter.dateFormat = settings.importDateFormat
        let importDate = formatter.string(from: Date())
        return root.appendingPathComponent(folderName).appendingPathComponent(importDate)
    }

    private func dateStringFor(fileURL: URL?) -> String? {
        guard settings.useDateFolder else { return nil }
        switch settings.dateSource {
        case .importDate:
            let formatter = DateFormatter()
            formatter.dateFormat = normalizedDatePattern(settings.importDateFormat)
            return formatter.string(from: Date())
        case .fileDate:
            guard let fileURL else { return nil }
            let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let date = values?.creationDate ?? values?.contentModificationDate
            guard let date else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = normalizedDatePattern(settings.importDateFormat)
            return formatter.string(from: date)
        case .none:
            return nil
        }
    }

    private func normalizedDatePattern(_ pattern: String) -> String {
        return pattern.replacingOccurrences(of: "m", with: "M")
    }

    private func progressValue(index: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(index) / Double(total)
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
}

struct SourceScan {
    let source: URL
    let photoFiles: [URL]
    let videoFiles: [URL]
    let hasDuplicates: Bool
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
    let fallbackDir: URL
    let type: MediaType
}

private enum DestinationResolution {
    case skip
    case transfer(URL, String?)
}

private struct ImportStateData {
    var knownSignatures: Set<String>
    var reservedSignatures: Set<String> = []
    var reservedTargets: Set<String> = []
    var result = TransferResult()
    var overallCompleted = 0
    var cardCompleted: [String: Int] = [:]
}

private final class ImportState {
    let maxConcurrentTransfers: Int
    private let state: Locked<ImportStateData>

    init(knownSignatures: Set<String>, maxConcurrentTransfers: Int) {
        self.maxConcurrentTransfers = maxConcurrentTransfers
        self.state = Locked(ImportStateData(knownSignatures: knownSignatures))
    }

    func resolveDestination(
        source: URL,
        proposedTarget: URL,
        signature: String?,
        duplicatePolicy: DuplicatePolicy
    ) -> DestinationResolution {
        state.withLock { data in
            let hasSignatureCollision = signature.map {
                data.knownSignatures.contains($0) || data.reservedSignatures.contains($0)
            } ?? false
            let targetPath = proposedTarget.path
            let hasTargetCollision = data.reservedTargets.contains(targetPath) || FileManager.default.fileExists(atPath: targetPath)
            let hasDuplicate = hasSignatureCollision || hasTargetCollision

            if hasDuplicate {
                data.result.duplicates += 1
                switch duplicatePolicy {
                case .skip, .prompt:
                    data.result.skipped += 1
                    return .skip
                case .keepBoth:
                    let unique = uniqueDestination(for: proposedTarget, reservedTargets: data.reservedTargets)
                    data.reservedTargets.insert(unique.path)
                    if let signature {
                        data.reservedSignatures.insert(signature)
                    }
                    return .transfer(unique, signature)
                case .overwrite:
                    if FileManager.default.fileExists(atPath: targetPath) {
                        try? FileManager.default.removeItem(at: proposedTarget)
                    }
                    data.reservedTargets.insert(targetPath)
                    if let signature {
                        data.reservedSignatures.insert(signature)
                    }
                    return .transfer(proposedTarget, signature)
                }
            }

            data.reservedTargets.insert(targetPath)
            if let signature {
                data.reservedSignatures.insert(signature)
            }
            return .transfer(proposedTarget, signature)
        }
    }

    func finishTransfer(target: URL, signature: String?, succeeded: Bool) {
        state.withLock { data in
            data.reservedTargets.remove(target.path)
            if let signature {
                data.reservedSignatures.remove(signature)
            }

            if succeeded {
                data.result.copied += 1
                if let signature {
                    data.knownSignatures.insert(signature)
                }
            } else {
                data.result.skipped += 1
            }
        }
    }

    func markCompleted(cardName: String, fileName: String, cardTotal: Int, totalFiles: Int) -> ProgressUpdate {
        state.withLock { data in
            data.overallCompleted += 1
            data.cardCompleted[cardName, default: 0] += 1
            let cardIndex = data.cardCompleted[cardName, default: 0]
            return ProgressUpdate(
                currentCard: cardName,
                currentFile: fileName,
                cardProgress: progressValue(index: cardIndex, total: cardTotal),
                overallProgress: progressValue(index: data.overallCompleted, total: totalFiles),
                overallIndex: data.overallCompleted
            )
        }
    }

    func snapshotResult() -> TransferResult {
        state.withLock { $0.result }
    }

    func snapshotKnownSignatures() -> Set<String> {
        state.withLock { $0.knownSignatures }
    }

    private func uniqueDestination(for target: URL, reservedTargets: Set<String>) -> URL {
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var counter = 1
        while true {
            let candidate = target.deletingLastPathComponent()
                .appendingPathComponent("\(base)_\(counter)")
                .appendingPathExtension(ext)
            if !reservedTargets.contains(candidate.path) && !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}

private func recommendedTransferConcurrency() -> Int {
    min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
}

private func progressValue(index: Int, total: Int) -> Double {
    guard total > 0 else { return 0 }
    return Double(index) / Double(total)
}
