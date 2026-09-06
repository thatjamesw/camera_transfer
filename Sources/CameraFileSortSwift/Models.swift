import Foundation

enum TransferAction: String, CaseIterable, Identifiable, Codable {
    case copy
    case move

    var id: String { rawValue }
}

enum DuplicatePolicy: String, CaseIterable, Identifiable, Codable {
    case prompt
    case skip
    case keepBoth
    case overwrite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prompt: return "Prompt"
        case .skip: return "Skip"
        case .keepBoth: return "Keep both"
        case .overwrite: return "Overwrite"
        }
    }
}

enum MediaSelection: String, CaseIterable, Identifiable, Codable {
    case photo
    case video
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .both: return "Photo + Video"
        }
    }
}

enum DestinationMode: String, CaseIterable, Identifiable, Codable {
    case separate
    case same
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .separate: return "Separate folders"
        case .same: return "Same folder"
        case .custom: return "Custom names"
        }
    }
}

enum DateSource: String, CaseIterable, Identifiable, Codable {
    case importDate
    case fileDate
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .importDate: return "Import date"
        case .fileDate: return "File date"
        case .none: return "None"
        }
    }
}

enum ImportTarget: String, CaseIterable, Identifiable, Codable {
    case sonyA1II = "Sony A1 II"
    case djiAvata2 = "DJI Avata 2"
    case djiMini5Pro = "DJI Mini 5 Pro"
    case djiPocket4Pro = "DJI Pocket 4 Pro"
    case misc = "Misc"

    var id: String { rawValue }
}

struct ImportDevice: Codable, Identifiable, Equatable {
    var id: String
    var name: String

    var folderName: String { Self.folderName(for: name) }

    static func folderName(for name: String) -> String {
        name.filter { !$0.isWhitespace }
    }

    static let defaults = ImportTarget.allCases.map { ImportDevice(id: $0.rawValue, name: $0.rawValue) }
}

struct AppSettings: Codable {
    var devices: [ImportDevice]? = nil
    var selectedDeviceID: String? = nil

    var availableDevices: [ImportDevice] { devices ?? ImportDevice.defaults }

    var selectedDevice: ImportDevice {
        availableDevices.first { $0.id == (selectedDeviceID ?? selectedTarget.rawValue) }
            ?? availableDevices.first ?? ImportDevice.defaults.last!
    }

    var activeDeviceID: String {
        get { selectedDevice.id }
        set { selectedDeviceID = newValue }
    }

    func deviceNameError(_ name: String, excluding id: String? = nil) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter a device name." }
        if name.hasPrefix(".") || name.contains("/") || name.contains(":") ||
            name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) ||
            name.utf8.count > 200 {
            return "Use a short folder name without slashes, colons, or a leading dot."
        }
        if availableDevices.contains(where: { $0.id != id && $0.folderName.compare(ImportDevice.folderName(for: name), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return "A device using this folder name already exists."
        }
        return nil
    }

    mutating func addDevice(named name: String) -> String? {
        if let error = deviceNameError(name) { return error }
        let device = ImportDevice(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        devices = availableDevices + [device]
        selectedDeviceID = device.id
        return nil
    }

    mutating func renameDevice(_ id: String, to name: String) -> String? {
        guard let index = availableDevices.firstIndex(where: { $0.id == id }) else { return "Device no longer exists." }
        if let error = deviceNameError(name, excluding: id) { return error }
        var updated = availableDevices
        updated[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        devices = updated
        return nil
    }

    mutating func removeDevice(_ id: String) {
        guard availableDevices.count > 1 else { return }
        let selectedID = activeDeviceID
        devices = availableDevices.filter { $0.id != id }
        selectedDeviceID = availableDevices.contains { $0.id == selectedID } ? selectedID : availableDevices.first?.id
    }

    // Optional storage keeps existing preferences decodable.
    var target: ImportTarget? = nil

    var selectedTarget: ImportTarget {
        get { target ?? .misc }
        set { target = newValue }
    }

    var targetRoot: URL {
        URL(fileURLWithPath: (destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath)
            .appendingPathComponent(selectedDevice.folderName, isDirectory: true)
    }

    var destinationConfigurationError: String? {
        let root = (destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard root.hasPrefix("/") else { return "Choose an absolute import folder." }
        guard Self.isSafeFolderName(selectedDevice.folderName) else { return "The device folder name is invalid." }
        guard availableDevices.filter({
            $0.folderName.compare(selectedDevice.folderName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }).count == 1 else { return "Two devices use this folder name. Rename one in Manage devices." }
        let folderNames: [String]
        switch destinationMode {
        case .separate: folderNames = ["photo", "video"]
        case .same: folderNames = [sameFolderName.isEmpty ? "media" : sameFolderName]
        case .custom: folderNames = [photoFolderName.isEmpty ? "photo" : photoFolderName, videoFolderName.isEmpty ? "video" : videoFolderName]
        }
        guard folderNames.allSatisfy(Self.isSafeFolderName) else {
            return "Use folder names without slashes, colons, or a leading dot."
        }
        if dateSource != .none {
            guard !importDateFormat.isEmpty, importDateFormat.count <= 64,
                  importDateFormat.allSatisfy({ "dMy-_".contains($0) }) else {
                return "Use a date pattern containing d, M, y, hyphens, or underscores."
            }
        }
        return nil
    }

    static func isSafeFolderName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !name.hasPrefix(".") && !name.contains("/") && !name.contains(":") &&
        name.utf8.count <= 200 &&
        !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    var destinationRoot: String
    var importDateFormat: String
    var action: TransferAction
    var photoExtensions: [String]
    var videoExtensions: [String]
    var includePaths: [String]
    var ejectAfter: Bool
    var duplicatePolicy: DuplicatePolicy
    var mediaSelection: MediaSelection
    var destinationMode: DestinationMode
    var sameFolderName: String
    var photoFolderName: String
    var videoFolderName: String
    var useDateFolder: Bool
    var dateSource: DateSource

    static let `default` = AppSettings(
        destinationRoot: "",
        importDateFormat: "MMddyyyy",
        action: .copy,
        photoExtensions: [
            ".3fr", ".arw", ".bay", ".cr2", ".cr3", ".crw", ".dcr",
            ".dng", ".erf", ".fff", ".gpr", ".heif", ".heic", ".hif", ".iiq", ".insp",
            ".jpg", ".jpeg", ".kdc", ".mef", ".mos", ".mrw", ".nef", ".nrw",
            ".orf", ".pef", ".png", ".raf", ".raw", ".rwl", ".rw2", ".sr2",
            ".srf", ".tif", ".tiff", ".x3f"
        ],
        videoExtensions: [
            ".3g2", ".3gp", ".ari", ".avi", ".braw", ".crm", ".insv", ".m2t",
            ".m2ts", ".m4v", ".mov", ".mp4", ".mpe", ".mpeg", ".mpg", ".mts",
            ".mxf", ".r3d", ".tod"
        ],
        includePaths: ["DCIM", "PRIVATE", "AVCHD", "MP_ROOT", "M4ROOT", "XDROOT", "CLIP", "CONTENTS"],
        ejectAfter: true,
        duplicatePolicy: .prompt,
        mediaSelection: .both,
        destinationMode: .separate,
        sameFolderName: "media",
        photoFolderName: "photo",
        videoFolderName: "video",
        useDateFolder: true,
        dateSource: .importDate
    )
}

struct TransferResult {
    var copied: Int = 0
    var skipped: Int = 0
    var duplicates: Int = 0
    var failed: Int = 0
    var transferFailures: [String] = []
    var ejectFailures: [String] = []
}
