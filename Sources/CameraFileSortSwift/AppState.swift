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

    private static let settingsKey = "CameraFileSortSwift.Settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
        refreshCards()
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

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose destination folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.destinationRoot = url.path
            destinationValid = validateDestination()
        }
    }

    func refreshCards() {
        detectedCards = CameraScanner.detectCards(includePaths: settings.includePaths)
        selectedCards = Set(detectedCards)
    }

    func scanMediaCounts() {
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
        let sources = Array(selectedCards)
        let settings = settings
        statusMessage = "Importing..."

        DispatchQueue.global(qos: .userInitiated).async {
            var mutableSettings = settings
            mutableSettings.duplicatePolicy = policy
            let importer = Importer(settings: mutableSettings)
            let result = importer.runImport(from: sources, scans: scans) { update in
                DispatchQueue.main.async {
                    self.currentCardName = update.currentCard
                    self.currentFileName = update.currentFile
                    self.cardProgress = update.cardProgress
                    self.overallProgress = update.overallProgress
                }
            }

            DispatchQueue.main.async {
                self.isImporting = false
                self.statusMessage = "Done. Copied \(result.copied), skipped \(result.skipped)."
                self.alert = AppAlert(
                    title: "Import complete",
                    message: "Copied \(result.copied). Skipped \(result.skipped). Duplicates \(result.duplicates)."
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

    private func normalizedDatePattern(_ pattern: String) -> String {
        return pattern.replacingOccurrences(of: "m", with: "M")
    }

    @discardableResult
    func validateDestination(createIfMissing: Bool = false) -> Bool {
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
