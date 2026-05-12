import AppKit
import Foundation
import SwiftUI

final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var detectedCards: [URL] = []
    @Published var selectedCards: Set<URL> = []
    @Published var isImporting = false
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
            if settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.destinationRoot = effectiveDefaultRoot(savedDefaultRoot: savedDefaultRoot)
            }
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
        let trimmed = settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.destinationRoot = trimmed
        guard validateDestination(createIfMissing: true, allowCreatablePath: true) else {
            alert = AppAlert(title: "Invalid path", message: "Please choose a valid destination folder.")
            return
        }
        UserDefaults.standard.set(trimmed, forKey: Self.defaultRootKey)
        refreshDefaultRootState()
    }

    func clearDefaultRoot() {
        UserDefaults.standard.removeObject(forKey: Self.defaultRootKey)
        refreshDefaultRootState()
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    func resetDefaults() {
        settings = .default
        saveSettings()
    }

    func resetDestinationDefaults() {
        guard !isImporting else { return }
        let def = AppSettings.default
        clearDefaultRoot()
        settings.destinationRoot = ""
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
        panel.title = "Choose destination folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.destinationRoot = url.path
            refreshDefaultRootState()
            destinationValid = validateDestination(allowCreatablePath: true)
        }
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
        guard !isImporting else { return }
        let sources = Array(selectedCards)
        guard !sources.isEmpty else {
            alert = AppAlert(title: "No cards selected", message: "Please select at least one card.")
            return
        }
        statusMessage = "Scanning media..."
        DispatchQueue.global(qos: .userInitiated).async {
            let importer = Importer(settings: self.settings)
            let scans = importer.scanSources(sources)
            let photoCount = scans.reduce(0) { $0 + $1.photoFiles.count }
            let videoCount = scans.reduce(0) { $0 + $1.videoFiles.count }
            let summary = "Photos: \(photoCount)  Videos: \(videoCount)"
            DispatchQueue.main.async {
                self.lastScanSummary = summary
                self.statusMessage = "Ready"
            }
        }
    }

    func startImport() {
        guard !isImporting else { return }
        let sources = Array(selectedCards)
        guard !sources.isEmpty else {
            alert = AppAlert(title: "No cards selected", message: "Please select at least one card.")
            return
        }
        guard validateDestination(createIfMissing: true) else {
            alert = AppAlert(
                title: "Destination invalid",
                message: "Please choose a valid destination folder."
            )
            return
        }

        isImporting = true
        statusMessage = "Scanning files..."
        overallProgress = 0
        cardProgress = 0
        currentCardName = ""
        currentFileName = ""
        processedCount = 0
        totalCount = 0

        DispatchQueue.global(qos: .userInitiated).async {
            let importer = Importer(settings: self.settings)
            let scans = importer.scanSources(sources)
            let duplicateFound = scans.contains { $0.hasDuplicates }
            let totalFiles = scans.reduce(0) { $0 + $1.photoFiles.count + $1.videoFiles.count }

            DispatchQueue.main.async {
                if totalFiles == 0 {
                    self.isImporting = false
                    self.statusMessage = "No media found."
                    self.alert = AppAlert(title: "No media found", message: "No matching files were found on the selected cards.")
                    return
                }
                self.totalCount = totalFiles
                if duplicateFound && self.settings.duplicatePolicy == .prompt {
                    self.alert = AppAlert(
                        title: "Duplicates detected",
                        message: "How should duplicates be handled?",
                        buttons: [
                            .init(title: "Skip", policy: .skip),
                            .init(title: "Keep both", policy: .keepBoth),
                            .init(title: "Overwrite", policy: .overwrite)
                        ],
                        onSelect: { policy in
                            self.runImport(with: policy, scans: scans)
                        }
                    )
                } else {
                    self.runImport(with: self.settings.duplicatePolicy, scans: scans)
                }
            }
        }
    }

    private func runImport(with policy: DuplicatePolicy, scans: [SourceScan]) {
        let settings = settings
        statusMessage = "Importing..."

        DispatchQueue.global(qos: .userInitiated).async {
            var mutableSettings = settings
            mutableSettings.duplicatePolicy = policy
            let importer = Importer(settings: mutableSettings)
            let result = importer.runImport(scans: scans) { update in
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
                self.cardProgress = 1
                self.overallProgress = 1
                self.processedCount = self.totalCount
                self.statusMessage = "Done. Copied \(result.copied), skipped \(result.skipped)."
                let ejectFailureMessage = result.ejectFailures.isEmpty
                    ? ""
                    : "\n\nEject issues:\n" + result.ejectFailures.joined(separator: "\n")
                self.alert = AppAlert(
                    title: "Import complete",
                    message: "Copied \(result.copied). Skipped \(result.skipped). Duplicates \(result.duplicates)." + ejectFailureMessage
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
        formatter.dateFormat = normalizedDatePattern(settings.importDateFormat)
        return formatter.string(from: Date())
    }

    func destinationPreview() -> String {
        let date = importDatePreview()
        let dateSuffix = date.isEmpty ? "" : "/\(date)"
        let root = settings.destinationRoot
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
        let trimmed = settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard validateDestination(createIfMissing: true, allowCreatablePath: true) else { return }
        let url = URL(fileURLWithPath: trimmed)
        NSWorkspace.shared.open(url)
    }

    private func normalizedDatePattern(_ pattern: String) -> String {
        return pattern.replacingOccurrences(of: "m", with: "M")
    }

    @discardableResult
    func validateDestination(createIfMissing: Bool = false, allowCreatablePath: Bool = false) -> Bool {
        let trimmed = settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            destinationValid = false
            return false
        }
        let url = URL(fileURLWithPath: trimmed)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            destinationValid = true
            return true
        }
        if allowCreatablePath, destinationParentExists(for: url) {
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
                return isDirectory.boolValue
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
        let trimmed = settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines)
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
                self?.handleVolumeEvent(notification)
            }
        }
    }

    private func handleVolumeEvent(_ notification: Notification) {
        let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
        let volumeName = notification.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String
        rebuildSources(selectAll: false, autoSelectNewSources: true)

        guard !isImporting else { return }
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

    private func rebuildSources(selectAll: Bool, autoSelectNewSources: Bool = false) {
        let previousDetectedPaths = Set(detectedCards.map(\.path))
        let previousSelectedPaths = Set(selectedCards.map(\.path))
        let autoDetected = CameraScanner.detectCards(includePaths: settings.includePaths)
        let merged = autoDetected + manualSources
        var seen = Set<String>()
        let unique = merged.filter { source in
            seen.insert(source.path).inserted
        }
        manualSources = manualSources.filter { source in
            unique.contains(where: { $0.path == source.path })
        }
        detectedCards = unique
        if selectAll {
            selectedCards = Set(unique)
        } else {
            let newSourcePaths = Set(unique.map(\.path)).subtracting(previousDetectedPaths)
            selectedCards = Set(unique.filter { source in
                previousSelectedPaths.contains(source.path) ||
                (autoSelectNewSources && newSourcePaths.contains(source.path))
            })
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
