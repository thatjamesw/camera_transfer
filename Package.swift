// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CameraFileSortSwift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CameraFileSortSwift", targets: ["CameraFileSortSwift"])
    ],
    targets: [
        .executableTarget(
            name: "CameraFileSortSwift",
            path: "Sources/CameraFileSortSwift"
        )
    ]
)
