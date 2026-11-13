import Foundation

/// How far a running export is, read from osxphotos's "Exporting NAME (…) (43/630)" log lines.
struct SyncProgress: Equatable {
    let currentItem: Int
    let totalItems: Int
    let currentFileName: String

    var fraction: Double { totalItems == 0 ? 0 : Double(currentItem) / Double(totalItems) }

    private static let exportingLine = #/\| Exporting (?<fileName>.+) \([^()]*\) \((?<current>\d+)/(?<total>\d+)\)\s*$/#

    /// The progress a log line reports, or nil for lines that don't report any.
    static func parse(logLine: String) -> SyncProgress? {
        guard let match = logLine.firstMatch(of: exportingLine),
              let currentItem = Int(match.current),
              let totalItems = Int(match.total)
        else { return nil }
        return SyncProgress(currentItem: currentItem, totalItems: totalItems, currentFileName: String(match.fileName))
    }
}

/// How the last sync ended.
enum SyncOutcome: Equatable {
    case finished
    case failed(exitCode: Int32)
    case cancelled
    case couldNotStart(reason: String)
}

/// The drive behind the chosen backup folder, as shown in the overview.
struct BackupDriveInfo: Equatable {
    let volumeName: String
    let freeBytes: Int64?

    /// Nil when the folder isn't reachable (usually: the drive is unplugged).
    static func read(backupFolder: String) -> BackupDriveInfo? {
        let folder = URL(fileURLWithPath: backupFolder)
        guard FileManager.default.fileExists(atPath: folder.path),
              let values = try? folder.resourceValues(forKeys: [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey])
        else { return nil }
        return BackupDriveInfo(
            volumeName: values.volumeName ?? folder.lastPathComponent,
            freeBytes: values.volumeAvailableCapacityForImportantUsage
        )
    }
}

/// Turns the CLI's error output into something a non-technical person can act on.
struct FriendlyError: Equatable {
    let title: String
    let advice: String

    static func describe(_ message: String) -> FriendlyError {
        if message.contains("Drive is not connected") {
            return FriendlyError(title: "Your backup drive isn't connected", advice: "Connect the drive, then click Try Again.")
        }
        if message.contains("must be on an external drive") {
            return FriendlyError(
                title: "Choose a folder on an external drive",
                advice: "Backups go to an external drive so your Mac doesn't fill up. Click Backup Folder… to pick one."
            )
        }
        if message.contains("Photos library not found") || message.contains("No System Photo Library") {
            return FriendlyError(title: "Couldn't find your Photos library", advice: "Open the Photos app once, then click Try Again.")
        }
        if message.contains("incomplete") {
            return FriendlyError(title: "Photos Backup Tracker needs reinstalling", advice: message)
        }
        return FriendlyError(title: "Something went wrong", advice: message)
    }
}
