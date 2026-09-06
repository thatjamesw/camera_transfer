import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var detectedCards: [URL] = []
    @Published var selectedCards: Set<URL> = []
    @Published var isImporting = false
    @Published var isScanning = false
    @Published var statusMessage = "Ready"
    @Published var alert: AppAlert? = nil
    @Published var overallProgress: Double = 0
    @Published var cardProgress: Double = 0
    @Published var currentCardName: String = ""
    @Published var currentFileName: String = ""
    @Published var destinationValid: Bool = true
    @Published var lastScanSummary: String = "Not scanned"
    @Published var processedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var importHadErrors = false

    private static let settingsKey = "CameraFileSortSwift.Settings"
    private static let defaultRootKey = "CameraFileSortSwift.DefaultRoot"
    private var manualSources: [URL] = []
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    @Published var hasDefaultRoot: Bool = false
    @Published var isCurrentDefaultRoot: Bool = false

    init() {
        let savedDefaultRoot = UserDefaults.standard.string(forKey: Self.defaultRootKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
            migrateSavedSettings()
            settings.destinationRoot = effectiveDefaultRoot(savedDefaultRoot: savedDefaultRoot)
        } else {
            settings = .default
            settings.destinationRoot = effectiveDefaultRoot(savedDefaultRoot: savedDefaultRoot)
        }
        refreshDefaultRootState()
        destinationValid = validateDestination(allowCreatablePath: true)
        refreshCards()
        startMonitoringVolumes()
    }

    deinit {
        for token in workspaceObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    func setDefaultRoot() {
        guard !isImporting else { return }
        let trimmed = (settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !trimmed.isEmpty else { return }
        settings.destinationRoot = trimmed
        guard validateDestination(createIfMissing: true, allowCreatablePath: true) else {
            alert = AppAlert(title: "Invalid path", message: "Please choose a valid destination folder.")
            return
        }
        UserDefaults.standard.set(trimmed, forKey: Self.defaultRootKey)
        refreshDefaultRootState()
        saveSettings()
    }

    func useDefaultRoot() {
        guard !isImporting else { return }
        settings.destinationRoot = UserDefaults.standard.string(forKey: Self.defaultRootKey) ?? ""
        destinationRootDidChange()
    }

    func clearDefaultRoot() {
        UserDefaults.standard.removeObject(forKey: Self.defaultRootKey)
        refreshDefaultRootState()
    }

    func saveSettings() {
        migrateSavedSettings()
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    func resetDefaults() {
        guard !isImporting else { return }
        settings = .default
        useDefaultRoot()
        saveSettings()
    }

    func resetDestinationDefaults() {
        guard !isImporting else { return }
        let def = AppSettings.default
        clearDefaultRoot()
        settings.destinationRoot = ""
        settings.target = nil
        settings.useDateFolder = def.useDateFolder
        settings.importDateFormat = def.importDateFormat
        settings.destinationMode = def.destinationMode
        settings.sameFolderName = def.sameFolderName
        settings.photoFolderName = def.photoFolderName
        settings.videoFolderName = def.videoFolderName
        settings.dateSource = def.dateSource
        refreshDefaultRootState()
        destinationValid = validateDestination(allowCreatablePath: true)
        saveSettings()
    }

    func resetTransferDefaults() {
        guard !isImporting else { return }
        let def = AppSettings.default
        settings.mediaSelection = def.mediaSelection
        settings.action = def.action
        settings.duplicatePolicy = def.duplicatePolicy
        settings.ejectAfter = def.ejectAfter
        saveSettings()
    }

    func chooseDestination() {
        guard !isImporting else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose your import folder"
        panel.message = "Device folders will be created inside this folder. Your choice is remembered."
        panel.prompt = "Use folder"
        if !settings.destinationRoot.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: settings.destinationRoot)
        }
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            rememberImportFolder(url)
        }
    }

    func rememberImportFolder(_ url: URL) {
        guard !isImporting else { return }
        let previousRoot = settings.destinationRoot
        settings.destinationRoot = url.standardizedFileURL.path
        guard validateDestination(allowCreatablePath: true) else {
            settings.destinationRoot = previousRoot
            destinationRootDidChange()
            alert = AppAlert(title: "Folder unavailable", message: "Choose a writable import folder.")
            return
        }
        UserDefaults.standard.set(settings.destinationRoot, forKey: Self.defaultRootKey)
        refreshDefaultRootState()
        saveSettings()
    }

    func chooseSource() {
        guard !isImporting else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose source drive or folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if panel.runModal() == .OK {
            manualSources.append(contentsOf: panel.urls)
            rebuildSources(selectAll: true)
        }
    }

    func destinationRootDidChange() {
        refreshDefaultRootState()
        destinationValid = validateDestination(allowCreatablePath: true)
    }

    func refreshCards() {
        guard !isImporting else { return }
        rebuildSources(selectAll: true)
    }

    func scanMediaCounts() {
        guard !isImporting, !isScanning else { return }
        let sources = selectedCards.sorted { $0.path < $1.path }
        guard !sources.isEmpty else {
            alert = AppAlert(title: "No cards selected", message: "Please select at least one card.")
            return
        }
        statusMessage = "Scanning media..."
        isScanning = true
        let settings = settings
        DispatchQueue.global(qos: .userInitiated).async {
            let importer = Importer(settings: settings)
            let scans = importer.scanSources(sources)
            let photoCount = scans.reduce(0) { $0 + $1.photoFiles.count }
            let videoCount = scans.reduce(0) { $0 + $1.videoFiles.count }
            let summary = "Photos: \(photoCount)  Videos: \(videoCount)"
            DispatchQueue.main.async {
                self.isScanning = false
                let errors = scans.flatMap(\.errors)
                self.lastScanSummary = errors.isEmpty ? summary : "Scan incomplete"
                self.statusMessage = errors.isEmpty ? "Ready" : "Scan failed"
                if !errors.isEmpty {
                    self.alert = AppAlert(title: "Cannot scan all files", message: errors.prefix(6).joined(separator: "\n"))
                }
            }
        }
    }

    func startImport() {
        guard !isImporting, !isScanning else { return }
        let sources = selectedCards.sorted { $0.path < $1.path }
        guard !sources.isEmpty else {
            alert = AppAlert(title: "No cards selected", message: "Please select at least one card.")
            return
        }
        if let error = settings.destinationConfigurationError {
            alert = AppAlert(title: "Invalid import settings", message: error)
            return
        }
        guard validateDestination(allowCreatablePath: true) else {
            alert = AppAlert(
                title: "Destination invalid",
                message: "Please choose a valid destination folder."
            )
            return
        }

        let target = settings.targetRoot.resolvingSymlinksInPath().standardizedFileURL.path
        guard !sources.contains(where: {
            let source = $0.resolvingSymlinksInPath().standardizedFileURL.path
            return target == source || target.hasPrefix(source + "/") || source.hasPrefix(target + "/")
        }) else {
            alert = AppAlert(title: "Overlapping folders", message: "Choose a destination outside the selected source folders.")
            return
        }
        let settings = settings
        isImporting = true
        importHadErrors = false
        statusMessage = "Scanning files..."
        overallProgress = 0
        cardProgress = 0
        currentCardName = ""
        currentFileName = ""
        processedCount = 0
        totalCount = 0

        DispatchQueue.global(qos: .userInitiated).async {
            let importer = Importer(settings: settings)
            let scans = importer.scanSources(sources)
            let duplicateFound = scans.contains { $0.hasDuplicates }
            let totalFiles = importer.transferFileCount(scans: scans)

            DispatchQueue.main.async {
                let errors = scans.flatMap(\.errors)
                if !errors.isEmpty {
                    self.isImporting = false
                    self.importHadErrors = true
                    self.statusMessage = "Scan failed"
                    self.alert = AppAlert(title: "Cannot scan all files", message: errors.prefix(6).joined(separator: "\n"))
                    return
                }
                if totalFiles == 0 {
                    self.isImporting = false
                    self.statusMessage = "No media found."
                    self.alert = AppAlert(title: "No media found", message: "No matching files were found on the selected cards.")
                    return
                }
                self.totalCount = totalFiles
                if duplicateFound && settings.duplicatePolicy == .prompt {
                    self.alert = AppAlert(
                        title: "Duplicates detected",
                        message: "How should duplicates be handled?",
                        buttons: [
                            .init(title: "Skip", policy: .skip),
                            .init(title: "Keep both", policy: .keepBoth),
                            .init(title: "Overwrite", policy: .overwrite)
                        ],
                        onSelect: { policy in
                            self.alert = nil
                            self.runImport(with: policy, scans: scans, settings: settings, importDate: importer.importDate)
                        }
                    )
                } else {
                    self.runImport(with: settings.duplicatePolicy, scans: scans, settings: settings, importDate: importer.importDate)
                }
            }
        }
    }

    private func runImport(with policy: DuplicatePolicy, scans: [SourceScan], settings: AppSettings, importDate: Date) {
        statusMessage = "Importing..."

        DispatchQueue.global(qos: .userInitiated).async {
            var mutableSettings = settings
            mutableSettings.duplicatePolicy = policy
            let importer = Importer(settings: mutableSettings, importDate: importDate)
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Importing camera media")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            var lastProgress = Date.distantPast
            let result = importer.runImport(scans: scans) { update in
                let now = Date()
                guard now.timeIntervalSince(lastProgress) >= 0.1 || update.overallProgress == 1 else { return }
                lastProgress = now
                DispatchQueue.main.async {
                    self.currentCardName = update.currentCard
                    self.currentFileName = update.currentFile
                    self.cardProgress = update.cardProgress
                    self.overallProgress = update.overallProgress
                    self.processedCount = update.overallIndex
                }
            }

            DispatchQueue.main.async {
                self.isImporting = false
                self.importHadErrors = result.failed > 0 || !result.ejectFailures.isEmpty
                self.cardProgress = 1
                self.overallProgress = 1
                self.processedCount = self.totalCount
                let verb = settings.action == .move ? "Moved" : "Copied"
                self.statusMessage = "Done. \(verb) \(result.copied), skipped \(result.skipped), failed \(result.failed)."
                let transferFailureMessage = result.transferFailures.isEmpty
                    ? ""
                    : "\n\nTransfer failures:\n" + result.transferFailures.prefix(6).joined(separator: "\n")
                        + (result.transferFailures.count > 6 ? "\n...and \(result.transferFailures.count - 6) more." : "")
                let ejectFailureMessage = result.ejectFailures.isEmpty
                    ? ""
                    : "\n\nEject issues:\n" + result.ejectFailures.joined(separator: "\n")
                self.alert = AppAlert(
                    title: self.importHadErrors ? "Import finished with errors" : "Import complete",
                    message: "\(verb) \(result.copied). Skipped \(result.skipped). Duplicates \(result.duplicates). Failed \(result.failed)." + transferFailureMessage + ejectFailureMessage
                )
                self.refreshCards()
            }
        }
    }

    func importDatePreview() -> String {
        if settings.dateSource == .none {
            return ""
        }
        if settings.dateSource == .fileDate {
            return "FILE_DATE"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = normalizedDatePattern(settings.importDateFormat)
        return formatter.string(from: Date())
    }

    func destinationPreview() -> String {
        let date = importDatePreview()
        let dateSuffix = date.isEmpty ? "" : "/\(date)"
        let root = settings.targetRoot.path
        switch settings.destinationMode {
        case .separate:
            return "\(root)/photo\(dateSuffix)  and  \(root)/video\(dateSuffix)"
        case .same:
            let folder = settings.sameFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "media"
                : settings.sameFolderName
            return "\(root)/\(folder)\(dateSuffix)"
        case .custom:
            let photoFolder = settings.photoFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "photo"
                : settings.photoFolderName
            let videoFolder = settings.videoFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "video"
                : settings.videoFolderName
            return "\(root)/\(photoFolder)\(dateSuffix)  and  \(root)/\(videoFolder)\(dateSuffix)"
        }
    }

    func openDestination() {
        guard !isImporting else { return }
        let trimmed = (settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !trimmed.isEmpty else { return }
        guard validateDestination(createIfMissing: true, allowCreatablePath: true) else { return }
        let url = settings.targetRoot
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            alert = AppAlert(title: "Cannot open destination", message: error.localizedDescription)
        }
    }

    private func normalizedDatePattern(_ pattern: String) -> String {
        return pattern.replacingOccurrences(of: "m", with: "M")
    }

    private func migrateSavedSettings() {
        let defaults = AppSettings.default
        settings.photoExtensions = mergedExtensions(settings.photoExtensions, defaults.photoExtensions)
        settings.videoExtensions = mergedExtensions(settings.videoExtensions, defaults.videoExtensions)
        settings.includePaths = mergedPaths(settings.includePaths, defaults.includePaths)
    }

    private func mergedExtensions(_ saved: [String], _ defaults: [String]) -> [String] {
        mergeCaseInsensitive(saved, defaults).map { extensionName in
            extensionName.hasPrefix(".") ? extensionName : ".\(extensionName)"
        }
    }

    private func mergedPaths(_ saved: [String], _ defaults: [String]) -> [String] {
        mergeCaseInsensitive(saved, defaults)
    }

    private func mergeCaseInsensitive(_ saved: [String], _ defaults: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for value in saved + defaults {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard seen.insert(trimmed.lowercased()).inserted else { continue }
            merged.append(trimmed)
        }
        return merged
    }

    @discardableResult
    func validateDestination(createIfMissing: Bool = false, allowCreatablePath: Bool = false) -> Bool {
        let trimmed = (settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !trimmed.isEmpty else {
            destinationValid = false
            return false
        }
        let url = URL(fileURLWithPath: trimmed)
        let components = url.pathComponents
        if components.count > 2, components[1] == "Volumes",
           !FileManager.default.fileExists(atPath: "/Volumes/" + components[2]) {
            destinationValid = false
            return false
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            destinationValid = isDir.boolValue && FileManager.default.isWritableFile(atPath: url.path)
            return destinationValid
        }
        if !createIfMissing, allowCreatablePath, destinationParentExists(for: url) {
            destinationValid = true
            return true
        }
        if createIfMissing {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                destinationValid = true
                return true
            } catch {
                destinationValid = false
                return false
            }
        }
        destinationValid = false
        return false
    }

    private func effectiveDefaultRoot(savedDefaultRoot: String? = nil) -> String {
        if let savedDefaultRoot, !savedDefaultRoot.isEmpty {
            return savedDefaultRoot
        }
        return ""
    }

    private func destinationParentExists(for url: URL) -> Bool {
        var current = url.deletingLastPathComponent()
        while current.path != url.path {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue && FileManager.default.isWritableFile(atPath: current.path)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return false
    }

    private func refreshDefaultRootState() {
        let savedDefaultRoot = UserDefaults.standard.string(forKey: Self.defaultRootKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = (settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        hasDefaultRoot = savedDefaultRoot?.isEmpty == false
        isCurrentDefaultRoot = hasDefaultRoot && savedDefaultRoot == trimmed
    }

    private func startMonitoringVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        let notifications: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]

        workspaceObserverTokens = notifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated { self?.handleVolumeEvent(notification) }
            }
        }
    }

    private func handleVolumeEvent(_ notification: Notification) {
        let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
        let volumeName = notification.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String
        rebuildSources(selectAll: false, autoSelectNewSources: true)

        guard !isImporting else { return }
        destinationRootDidChange()
        switch notification.name {
        case NSWorkspace.didMountNotification:
            statusMessage = "Mounted \(volumeName ?? volumeURL?.lastPathComponent ?? "volume")"
        case NSWorkspace.didUnmountNotification:
            statusMessage = "Unmounted \(volumeName ?? volumeURL?.lastPathComponent ?? "volume")"
        case NSWorkspace.didRenameVolumeNotification:
            statusMessage = "Updated \(volumeName ?? volumeURL?.lastPathComponent ?? "volume")"
        default:
            break
        }
    }

    private var sourceRefreshGeneration = 0

    private func rebuildSources(selectAll: Bool, autoSelectNewSources: Bool = false) {
        sourceRefreshGeneration += 1
        let generation = sourceRefreshGeneration
        let paths = settings.includePaths
        let manual = manualSources
        DispatchQueue.global(qos: .utility).async {
            let detected = CameraScanner.detectCards(includePaths: paths)
            let existing = manual.filter { FileManager.default.fileExists(atPath: $0.path) }
            var seen = Set<String>()
            let unique = (detected + existing).filter { seen.insert($0.standardizedFileURL.path).inserted }
            DispatchQueue.main.async {
                guard generation == self.sourceRefreshGeneration else { return }
                let previousDetected = Set(self.detectedCards.map(\.path))
                let previousSelected = Set(self.selectedCards.map(\.path))
                self.manualSources = existing
                self.detectedCards = unique
                if selectAll {
                    self.selectedCards = Set(unique)
                } else {
                    self.selectedCards = Set(unique.filter {
                        previousSelected.contains($0.path) ||
                        (autoSelectNewSources && !previousDetected.contains($0.path))
                    })
                }
            }
        }
    }

}

struct AppAlert: Identifiable {
    struct ButtonAction {
        let title: String
        let policy: DuplicatePolicy
    }

    let id = UUID()
    let title: String
    let message: String
    var buttons: [ButtonAction] = []
    var onSelect: ((DuplicatePolicy) -> Void)? = nil
}
