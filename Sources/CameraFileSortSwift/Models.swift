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

struct AppSettings: Codable {
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
        photoExtensions: [".arw", ".jpg", ".jpeg", ".heif", ".hif", ".tif", ".tiff", ".png"],
        videoExtensions: [".mp4", ".mov", ".mxf", ".mts"],
        includePaths: ["DCIM", "PRIVATE"],
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
}
