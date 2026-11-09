// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PhotosBackupTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PhotosBackupTracker", path: "Sources/PhotosBackupTracker"),
        .testTarget(
            name: "PhotosBackupTrackerTests",
            dependencies: ["PhotosBackupTracker"],
            path: "Tests/PhotosBackupTrackerTests"
        ),
    ]
)
