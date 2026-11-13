import Foundation
import Observation

@MainActor
@Observable
final class BackupStore {
    static let maximumLogLines = 2_000

    /// The folder on the external drive that holds the backup; nil until the user picks one.
    private(set) var backupTarget: String?
    private(set) var libraryNode: ProgressNode?
    private(set) var nodesByID: [String: ProgressNode] = [:]
    private(set) var isLoading = false
    private(set) var loadError: String?

    /// Title of the period being synced right now, e.g. "December 2016".
    private(set) var activeSyncTitle: String?
    private(set) var syncProgress: SyncProgress?
    private(set) var syncLog: [String] = []
    /// Title and outcome of the last finished sync, until dismissed or a new sync starts.
    private(set) var lastSyncTitle: String?
    private(set) var lastSyncOutcome: SyncOutcome?

    private let commandRunner: any CommandRunning
    private let saveBackupTarget: (String) -> Void
    private let readDriveInfo: (String) -> BackupDriveInfo?
    private var syncTask: Task<Void, Never>?

    init(
        commandRunner: any CommandRunning,
        backupTarget: String?,
        saveBackupTarget: @escaping (String) -> Void = { _ in },
        readDriveInfo: @escaping (String) -> BackupDriveInfo? = BackupDriveInfo.read(backupFolder:)
    ) {
        self.commandRunner = commandRunner
        self.backupTarget = backupTarget
        self.saveBackupTarget = saveBackupTarget
        self.readDriveInfo = readDriveInfo
    }

    /// The drive behind the backup folder, or nil when no folder is chosen or the drive is unplugged.
    var backupDrive: BackupDriveInfo? {
        backupTarget.flatMap(readDriveInfo)
    }

    var isSyncing: Bool { activeSyncTitle != nil }

    var lastSyncSummary: String? {
        guard let lastSyncTitle, let lastSyncOutcome else { return nil }
        switch lastSyncOutcome {
        case .finished: return "\(lastSyncTitle): finished"
        case .failed(let exitCode): return "\(lastSyncTitle): failed with exit code \(exitCode) — see the details"
        case .cancelled: return "\(lastSyncTitle): cancelled"
        case .couldNotStart(let reason): return "\(lastSyncTitle): could not start — \(reason)"
        }
    }

    /// Switches to another backup folder, remembers it, and recounts.
    func chooseBackupTarget(_ path: String) async {
        guard !isSyncing else { return }
        backupTarget = path
        saveBackupTarget(path)
        libraryNode = nil
        nodesByID = [:]
        await reload()
    }

    func reload() async {
        guard let backupTarget else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let result = try await commandRunner.run(["progress", backupTarget])
            guard result.exitCode == 0 else {
                loadError = result.standardError.isEmpty ? "photos-backup progress failed (exit code \(result.exitCode))" : result.standardError
                return
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let report = try decoder.decode(ProgressReport.self, from: result.standardOutput)
            let library = ProgressTreeBuilder.buildLibrary(from: report.days)
            libraryNode = library
            nodesByID = library.indexedByID()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Starts exporting the node's date range; returns nil when nothing was started.
    @discardableResult
    func sync(_ node: ProgressNode) -> Task<Void, Never>? {
        guard node.canBeSynced, !isSyncing, let backupTarget else { return nil }
        activeSyncTitle = node.title
        syncProgress = nil
        syncLog = []
        lastSyncTitle = nil
        lastSyncOutcome = nil

        let task = Task {
            let outcome: SyncOutcome
            do {
                let exitCode = try await commandRunner.stream(
                    ["export", "--from", node.firstDay, "--to", node.lastDay, backupTarget]
                ) { line in
                    await self.appendLogLine(line)
                }
                outcome = Task.isCancelled ? .cancelled : (exitCode == 0 ? .finished : .failed(exitCode: exitCode))
            } catch {
                outcome = Task.isCancelled ? .cancelled : .couldNotStart(reason: error.localizedDescription)
            }
            lastSyncTitle = node.title
            lastSyncOutcome = outcome
            activeSyncTitle = nil
            syncProgress = nil
            syncTask = nil
            await reload()
        }
        syncTask = task
        return task
    }

    /// Stops the running sync. Files already copied stay on the drive; syncing again continues where it stopped.
    func cancelSync() {
        syncTask?.cancel()
    }

    func dismissSyncResult() {
        guard !isSyncing else { return }
        lastSyncTitle = nil
        lastSyncOutcome = nil
        syncLog = []
    }

    private func appendLogLine(_ line: String) {
        syncLog.append(line)
        if syncLog.count > Self.maximumLogLines {
            syncLog.removeFirst(syncLog.count - Self.maximumLogLines)
        }
        if let progress = SyncProgress.parse(logLine: line) {
            syncProgress = progress
        }
    }
}
