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
    private(set) var activeSyncTitle: String?
    private(set) var syncLog: [String] = []
    private(set) var lastSyncSummary: String?

    private let commandRunner: any CommandRunning
    private let saveBackupTarget: (String) -> Void

    init(commandRunner: any CommandRunning, backupTarget: String?, saveBackupTarget: @escaping (String) -> Void = { _ in }) {
        self.commandRunner = commandRunner
        self.backupTarget = backupTarget
        self.saveBackupTarget = saveBackupTarget
    }

    var isSyncing: Bool { activeSyncTitle != nil }

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
        syncLog = []
        lastSyncSummary = nil

        return Task {
            do {
                let exitCode = try await commandRunner.stream(
                    ["export", "--from", node.firstDay, "--to", node.lastDay, backupTarget]
                ) { line in
                    await self.appendLogLine(line)
                }
                lastSyncSummary = exitCode == 0
                    ? "\(node.title): finished"
                    : "\(node.title): failed with exit code \(exitCode) — see the log below"
            } catch {
                lastSyncSummary = "\(node.title): could not start — \(error.localizedDescription)"
            }
            activeSyncTitle = nil
            await reload()
        }
    }

    private func appendLogLine(_ line: String) {
        syncLog.append(line)
        if syncLog.count > Self.maximumLogLines {
            syncLog.removeFirst(syncLog.count - Self.maximumLogLines)
        }
    }
}
