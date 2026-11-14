import Foundation
import Testing
@testable import PhotosBackupTracker

private struct LaunchFailure: Error, LocalizedError {
    var errorDescription: String? { "uv not found" }
}

/// Records every CLI call and answers with canned results.
private actor FakeCommandRunner: CommandRunning {
    private(set) var calls: [[String]] = []
    private var progressResult = CommandResult(exitCode: 0, standardOutput: progressJSON([]), standardError: "")
    private var exportLines: [String] = []
    private var exportExitCode: Int32 = 0
    private var exportLaunchFails = false
    private var holdsExportsOpen = false
    private var waitsForCancellationAfterLines = false
    private var exportGate: CheckedContinuation<Void, Never>?

    var exportCalls: [[String]] { calls.filter { $0.first == "export" } }

    func run(_ arguments: [String]) async throws -> CommandResult {
        calls.append(arguments)
        return progressResult
    }

    func stream(_ arguments: [String], onLine: @escaping @Sendable (String) async -> Void) async throws -> Int32 {
        calls.append(arguments)
        if exportLaunchFails { throw LaunchFailure() }
        if holdsExportsOpen { await withCheckedContinuation { exportGate = $0 } }
        for line in exportLines { await onLine(line) }
        if waitsForCancellationAfterLines {
            do { try await Task.sleep(for: .seconds(60)) } catch { return 143 }
        }
        return exportExitCode
    }

    func answerProgress(_ result: CommandResult) { progressResult = result }
    func answerExport(lines: [String], exitCode: Int32 = 0) { exportLines = lines; exportExitCode = exitCode }
    func failExportLaunches() { exportLaunchFails = true }
    func holdExportsOpen() { holdsExportsOpen = true }
    func waitForCancellationAfterLines() { waitsForCancellationAfterLines = true }
    func releaseExport() { exportGate?.resume(); exportGate = nil }
}

private func progressJSON(_ days: [(String, Int, Int)]) -> Data {
    let entries = days.map { #"{"day": "\#($0.0)", "total_items": \#($0.1), "synced_items": \#($0.2), "hidden_items": 0}"# }
    return Data(#"{"days": [\#(entries.joined(separator: ","))]}"#.utf8)
}

private func successfulProgress(_ days: [(String, Int, Int)]) -> CommandResult {
    CommandResult(exitCode: 0, standardOutput: progressJSON(days), standardError: "")
}

private let target = "/Volumes/Test Drive/Photos"

private struct NodeNotFound: Error {}

@MainActor
private final class SavedFolders {
    private(set) var paths: [String] = []
    func save(_ path: String) { paths.append(path) }
}

@MainActor
@Suite("Backup store")
struct BackupStoreTests {
    private let runner = FakeCommandRunner()
    private let store: BackupStore

    init() {
        store = BackupStore(commandRunner: runner, backupTarget: target)
    }

    private func load(_ days: [(String, Int, Int)]) async {
        await runner.answerProgress(successfulProgress(days))
        await store.reload()
    }

    private func node(_ id: String) throws -> ProgressNode {
        guard let node = store.nodesByID[id] else { throw NodeNotFound() }
        return node
    }

    /// Starts a sync and waits for it, including the refresh afterwards.
    private func syncAndWait(_ id: String) async throws {
        let syncTask = try #require(store.sync(try node(id)))
        await syncTask.value
    }

    // MARK: Loading counts

    @Test func reloadAsksTheCLIForProgressOfTheBackupDrive() async {
        await store.reload()
        #expect(await runner.calls == [["progress", target]])
    }

    @Test func reloadBuildsTheTree() async throws {
        await load([("2026-02-14", 2, 2), ("2026-03-20", 18, 5)])

        let library = try #require(store.libraryNode)
        #expect((library.totalItems, library.syncedItems) == (20, 7))
        #expect(try node("2026-03-20").missingItems == 13)
        #expect(store.loadError == nil)
        #expect(store.isLoading == false)
    }

    @Test func reloadFailureShowsTheCLIsErrorMessage() async {
        await runner.answerProgress(CommandResult(exitCode: 1, standardOutput: Data(), standardError: "Drive is not connected: /Volumes/Test Drive"))

        await store.reload()

        #expect(store.loadError == "Drive is not connected: /Volumes/Test Drive")
        #expect(store.libraryNode == nil)
    }

    @Test func reloadFailureWithoutMessageNamesTheExitCode() async {
        await runner.answerProgress(CommandResult(exitCode: 9, standardOutput: Data(), standardError: ""))

        await store.reload()

        #expect(store.loadError?.contains("exit code 9") == true)
    }

    @Test func unreadableJSONIsReportedAsAnError() async {
        await runner.answerProgress(CommandResult(exitCode: 0, standardOutput: Data("not json".utf8), standardError: ""))

        await store.reload()

        #expect(store.loadError != nil)
        #expect(store.libraryNode == nil)
    }

    @Test func successfulReloadClearsAnEarlierError() async {
        await runner.answerProgress(CommandResult(exitCode: 1, standardOutput: Data(), standardError: "unplugged"))
        await store.reload()

        await load([("2026-02-14", 2, 2)])

        #expect(store.loadError == nil)
        #expect(store.libraryNode != nil)
    }

    // MARK: Choosing the backup folder

    @Test func withoutABackupFolderNothingRuns() async {
        let storeWithoutFolder = BackupStore(commandRunner: runner, backupTarget: nil)

        await storeWithoutFolder.reload()

        #expect(await runner.calls.isEmpty)
        #expect(storeWithoutFolder.libraryNode == nil)
        #expect(storeWithoutFolder.loadError == nil)
    }

    @Test func choosingAFolderSavesItAndCountsAgainstIt() async {
        let savedFolders = SavedFolders()
        let storeWithoutFolder = BackupStore(commandRunner: runner, backupTarget: nil, saveBackupTarget: savedFolders.save)
        await runner.answerProgress(successfulProgress([("2026-02-14", 2, 1)]))

        await storeWithoutFolder.chooseBackupTarget("/Volumes/New Drive/Photos")

        #expect(storeWithoutFolder.backupTarget == "/Volumes/New Drive/Photos")
        #expect(savedFolders.paths == ["/Volumes/New Drive/Photos"])
        #expect(await runner.calls == [["progress", "/Volumes/New Drive/Photos"]])
        #expect(storeWithoutFolder.libraryNode?.missingItems == 1)
    }

    @Test func syncUsesTheChosenFolder() async throws {
        await load([("2026-03-20", 18, 0)])
        await store.chooseBackupTarget("/Volumes/Other Drive/Backup")

        try await syncAndWait("2026-03-20")

        #expect(await runner.exportCalls.last?.last == "/Volumes/Other Drive/Backup")
    }

    // MARK: Syncing

    @Test func syncingAMonthExportsTheWholeMonthAndStreamsTheLog() async throws {
        await load([("2024-02-10", 3, 0)])
        await runner.answerExport(lines: ["Exporting IMG_1.HEIC (1/3)", "Exporting IMG_2.HEIC (2/3)", "Check passed"])
        let februaryTitle = try node("2024-02").title

        try await syncAndWait("2024-02")

        #expect(await runner.exportCalls == [["export", "--from", "2024-02-01", "--to", "2024-02-29", target]])
        #expect(store.syncLog == ["Exporting IMG_1.HEIC (1/3)", "Exporting IMG_2.HEIC (2/3)", "Check passed"])
        #expect(store.lastSyncSummary == "\(februaryTitle): finished")
        #expect(store.isSyncing == false)
    }

    @Test func syncingADayExportsJustThatDay() async throws {
        await load([("2026-03-20", 18, 0)])

        try await syncAndWait("2026-03-20")

        #expect(await runner.exportCalls == [["export", "--from", "2026-03-20", "--to", "2026-03-20", target]])
    }

    @Test func countsAreRefreshedAfterASync() async throws {
        await load([("2026-03-20", 18, 0)])
        await runner.answerProgress(successfulProgress([("2026-03-20", 18, 18)]))

        try await syncAndWait("2026-03-20")

        #expect(await runner.calls.map(\.first) == ["progress", "export", "progress"])
        #expect(store.libraryNode?.missingItems == 0)
    }

    @Test func failedExportIsSummarisedWithItsExitCode() async throws {
        await load([("2026-03-20", 18, 0)])
        await runner.answerExport(lines: ["Error: could not get authorization"], exitCode: 3)

        try await syncAndWait("2026-03-20")

        #expect(store.lastSyncSummary?.contains("failed with exit code 3") == true)
        #expect(store.syncLog == ["Error: could not get authorization"])
    }

    @Test func exportThatCannotStartIsSummarised() async throws {
        await load([("2026-03-20", 18, 0)])
        await runner.failExportLaunches()

        try await syncAndWait("2026-03-20")

        #expect(store.lastSyncSummary?.contains("could not start — uv not found") == true)
        #expect(store.isSyncing == false)
    }

    @Test func theWholeLibraryCannotBeSyncedAtOnce() async throws {
        await load([("2026-03-20", 18, 0)])

        #expect(store.sync(try node("library")) == nil)
        #expect(await runner.exportCalls.isEmpty)
    }

    @Test func syncingAYearExportsTheWholeYear() async throws {
        await load([("2016-12-24", 334, 0), ("2016-02-14", 5, 0)])

        try await syncAndWait("2016")

        #expect(await runner.exportCalls == [["export", "--from", "2016-01-01", "--to", "2016-12-31", target]])
    }

    @Test func onlyOneSyncRunsAtATime() async throws {
        await load([("2026-03-20", 18, 0), ("2026-02-14", 2, 0)])
        await runner.holdExportsOpen()

        let firstSync = try #require(store.sync(try node("2026-03-20")))
        #expect(store.isSyncing)
        #expect(store.activeSyncTitle == (try node("2026-03-20")).title)
        #expect(store.sync(try node("2026-02-14")) == nil)

        while await runner.exportCalls.isEmpty { await Task.yield() }
        await runner.releaseExport()
        await firstSync.value

        #expect(await runner.exportCalls.count == 1)
        #expect(store.isSyncing == false)
    }

    @Test func newSyncClearsThePreviousLog() async throws {
        await load([("2026-03-20", 18, 0)])
        await runner.answerExport(lines: ["first run"])
        try await syncAndWait("2026-03-20")

        await runner.answerExport(lines: ["second run"])
        try await syncAndWait("2026-03-20")

        #expect(store.syncLog == ["second run"])
    }

    @Test func logKeepsOnlyTheNewestLines() async throws {
        await load([("2026-03-20", 18, 0)])
        await runner.answerExport(lines: (1...(BackupStore.maximumLogLines + 50)).map { "line \($0)" })

        try await syncAndWait("2026-03-20")

        #expect(store.syncLog.count == BackupStore.maximumLogLines)
        #expect(store.syncLog.first == "line 51")
        #expect(store.syncLog.last == "line \(BackupStore.maximumLogLines + 50)")
    }
}

@MainActor
@Suite("Backup store: progress and cancelling")
struct BackupStoreSyncLifecycleTests {
    private let runner = FakeCommandRunner()
    private let store: BackupStore

    init() {
        store = BackupStore(commandRunner: runner, backupTarget: target)
    }

    private func loadAndFind(_ id: String) async throws -> ProgressNode {
        await runner.answerProgress(successfulProgress([("2016-12-24", 630, 0)]))
        await store.reload()
        return try #require(store.nodesByID[id])
    }

    @Test func progressFollowsTheExportingLinesWhileSyncing() async throws {
        let day = try await loadAndFind("2016-12-24")
        await runner.answerExport(lines: [
            "2026-11-09 19:45:14,466 INFO    osxphotos | Exporting IMG_0559.JPG (57BB5311.jpeg) (40/630)",
            "2026-11-09 19:45:16,015 INFO    osxphotos | Exporting IMG_0561.PNG (A1C64566.png) (42/630)",
        ])
        await runner.waitForCancellationAfterLines()

        let syncing = try #require(store.sync(day))
        while store.syncProgress?.currentItem != 42 { await Task.yield() }

        #expect(store.syncProgress == SyncProgress(currentItem: 42, totalItems: 630, currentFileName: "IMG_0561.PNG"))
        store.cancelSync()
        await syncing.value
        #expect(store.syncProgress == nil)
    }

    @Test func cancellingStopsTheSyncAndSaysSo() async throws {
        let day = try await loadAndFind("2016-12-24")
        await runner.waitForCancellationAfterLines()

        let syncing = try #require(store.sync(day))
        while await runner.exportCalls.isEmpty { await Task.yield() }
        store.cancelSync()
        await syncing.value

        #expect(store.lastSyncOutcome == .cancelled)
        #expect(store.lastSyncSummary == "\(day.title): cancelled")
        #expect(store.isSyncing == false)
        #expect(await runner.calls.map(\.first) == ["progress", "export", "progress"])
    }

    @Test func cancelWithoutASyncDoesNothing() {
        store.cancelSync()
        #expect(store.isSyncing == false)
        #expect(store.lastSyncOutcome == nil)
    }

    @Test func finishedSyncIsReportedUntilDismissed() async throws {
        let day = try await loadAndFind("2016-12-24")
        await runner.answerExport(lines: ["done"])

        try await #require(store.sync(day)).value
        #expect(store.lastSyncOutcome == .finished)
        #expect(store.lastSyncTitle == day.title)

        store.dismissSyncResult()
        #expect(store.lastSyncOutcome == nil)
        #expect(store.lastSyncTitle == nil)
        #expect(store.syncLog.isEmpty)
    }
}
