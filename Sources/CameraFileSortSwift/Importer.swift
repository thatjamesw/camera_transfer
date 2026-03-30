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

struct Importer {
    let settings: AppSettings

    func scanSources(_ sources: [URL]) -> [SourceScan] {
        let knownSignatures = loadManifest()
        var scans: [SourceScan] = []
        for source in sources {
            let photoFiles = shouldInclude(.photo) ? gatherFiles(in: source, extensions: settings.photoExtensions) : []
            let videoFiles = shouldInclude(.video) ? gatherFiles(in: source, extensions: settings.videoExtensions) : []
            let photoHasDup = shouldInclude(.photo) && hasDuplicatesForFiles(files: photoFiles, type: .photo, knownSignatures: knownSignatures)
            let videoHasDup = shouldInclude(.video) && hasDuplicatesForFiles(files: videoFiles, type: .video, knownSignatures: knownSignatures)
            scans.append(
                SourceScan(
                    source: source,
                    photoFiles: photoFiles,
                    videoFiles: videoFiles,
                    hasDuplicates: photoHasDup || videoHasDup
                )
            )
        }
        return scans
    }

    func runImport(
        from sources: [URL],
        scans: [SourceScan],
        onProgress: ((ProgressUpdate) -> Void)? = nil
    ) -> TransferResult {
        var result = TransferResult()
        var knownSignatures = loadManifest()
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
        var overallIndex = 0

        for scan in scans {
            let cardTotal = scan.photoFiles.count + scan.videoFiles.count
            var cardIndexCount = 0
            let cardName = scan.source.lastPathComponent

            var photoResult = TransferResult()
            var videoResult = TransferResult()
            if shouldInclude(.photo) {
                photoResult = transfer(files: scan.photoFiles, to: photoDir, type: .photo, knownSignatures: &knownSignatures) { file in
                    overallIndex += 1
                    cardIndexCount += 1
                    onProgress?(ProgressUpdate(
                        currentCard: cardName,
                        currentFile: file.lastPathComponent,
                        cardProgress: progressValue(index: cardIndexCount, total: cardTotal),
                        overallProgress: progressValue(index: overallIndex, total: totalFiles),
                        overallIndex: overallIndex
                    ))
                }
            }

            if shouldInclude(.video) {
                videoResult = transfer(files: scan.videoFiles, to: videoDir, type: .video, knownSignatures: &knownSignatures) { file in
                    overallIndex += 1
                    cardIndexCount += 1
                    onProgress?(ProgressUpdate(
                        currentCard: cardName,
                        currentFile: file.lastPathComponent,
                        cardProgress: progressValue(index: cardIndexCount, total: cardTotal),
                        overallProgress: progressValue(index: overallIndex, total: totalFiles),
                        overallIndex: overallIndex
                    ))
                }
            }

            result.copied += photoResult.copied + videoResult.copied
            result.skipped += photoResult.skipped + videoResult.skipped
            result.duplicates += photoResult.duplicates + videoResult.duplicates

        }

        if result.copied > 0 {
            saveManifest(knownSignatures)
        }

        if settings.ejectAfter {
            for scan in scans {
                eject(volume: scan.source)
            }
            eject(volume: URL(fileURLWithPath: "/Volumes/PMHOME"))
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

    private func transfer(
        files: [URL],
        to destDir: URL,
        type: MediaType,
        knownSignatures: inout Set<String>,
        onFile: ((URL) -> Void)? = nil
    ) -> TransferResult {
        var result = TransferResult()
        for file in files {
            let actualDestDir = destinationDir(type: type, fileURL: file, fallback: destDir)
            createDirectory(actualDestDir)
            let target = actualDestDir.appendingPathComponent(file.lastPathComponent)
            let signature = fileSignature(for: file)
            let hasPotentialDuplicate = signature.map { knownSignatures.contains($0) } ?? false

            if FileManager.default.fileExists(atPath: target.path) || hasPotentialDuplicate {
                result.duplicates += 1
                switch settings.duplicatePolicy {
                case .skip:
                    result.skipped += 1
                    continue
                case .keepBoth:
                    let unique = uniqueDestination(for: target)
                    moveOrCopy(file, to: unique, result: &result, signature: signature, knownSignatures: &knownSignatures)
                case .overwrite:
                    if FileManager.default.fileExists(atPath: target.path) {
                        try? FileManager.default.removeItem(at: target)
                    }
                    moveOrCopy(file, to: target, result: &result, signature: signature, knownSignatures: &knownSignatures)
                case .prompt:
                    result.skipped += 1
                }
            } else {
                moveOrCopy(file, to: target, result: &result, signature: signature, knownSignatures: &knownSignatures)
            }
            onFile?(file)
        }
        return result
    }

    private func moveOrCopy(
        _ file: URL,
        to target: URL,
        result: inout TransferResult,
        signature: String?,
        knownSignatures: inout Set<String>
    ) {
        do {
            if settings.action == .move {
                try FileManager.default.moveItem(at: file, to: target)
            } else {
                try FileManager.default.copyItem(at: file, to: target)
            }
            result.copied += 1
            if let signature {
                knownSignatures.insert(signature)
            }
        } catch {
            result.skipped += 1
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

    private func eject(volume: URL) {
        guard FileManager.default.fileExists(atPath: volume.path) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["eject", volume.path]
        try? task.run()
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
