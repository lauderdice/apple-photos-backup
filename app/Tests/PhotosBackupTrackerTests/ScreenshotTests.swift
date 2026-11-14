import AppKit
import SwiftUI
import Testing
@testable import PhotosBackupTracker

// Renders the README screenshots from made-up demo data, so they never show anyone's real library or drive.
// Runs only when PHOTOS_BACKUP_SCREENSHOTS_FOLDER is set: `make screenshots`.

private let screenshotsFolder = ProcessInfo.processInfo.environment["PHOTOS_BACKUP_SCREENSHOTS_FOLDER"]
private let demoBackupFolder = "/Volumes/Backup Drive/Photos Backup"
private let demoDrive = BackupDriveInfo(volumeName: "Backup Drive", freeBytes: 1_284_000_000_000)
private let windowSize = CGSize(width: 900, height: 640)
private let appIconFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../docs/icon.png").standardized

/// A library from 2014 to 2026: older years backed up, December 2016 partly, 2017 half, newer years not yet.
private func demoProgressJSON() -> Data {
    var entries: [String] = []
    for year in 2014...2026 {
        for month in 1...12 where !(year == 2026 && month > 10) {
            for (position, day) in [3, 8, 14, 21, 27].enumerated() {
                let total = 4 + (year * 7 + month * 13 + day) % 37
                let synced: Int
                switch (year, month) {
                case (..<2016, _): synced = total
                case (2016, 12): synced = position == 0 ? total : (position == 1 ? total / 3 : 0)
                case (2016, _): synced = total
                case (2017, ...5): synced = total
                default: synced = 0
                }
                let hidden = (year == 2016 && month % 4 == 3 && position == 4) ? 2 : 0
                entries.append(String(format: #"{"day": "%04d-%02d-%02d", "total_items": %d, "synced_items": %d, "hidden_items": %d}"#, year, month, day, total, synced, hidden))
            }
        }
    }
    return Data(#"{"days": [\#(entries.joined(separator: ","))]}"#.utf8)
}

private actor DemoCommandRunner: CommandRunning {
    let progress: CommandResult
    let exportLines: [String]
    let exportRunsUntilCancelled: Bool

    init(progress: CommandResult, exportLines: [String] = [], exportRunsUntilCancelled: Bool = false) {
        self.progress = progress
        self.exportLines = exportLines
        self.exportRunsUntilCancelled = exportRunsUntilCancelled
    }

    func run(_ arguments: [String]) async throws -> CommandResult { progress }

    func stream(_ arguments: [String], onLine: @escaping @Sendable (String) async -> Void) async throws -> Int32 {
        for line in exportLines { await onLine(line) }
        if exportRunsUntilCancelled {
            do { try await Task.sleep(for: .seconds(3600)) } catch { return 143 }
        }
        return 0
    }
}

private let demoProgress = CommandResult(exitCode: 0, standardOutput: demoProgressJSON(), standardError: "")

private let demoExportLines = (1...214).map { item in
    "2026-11-13 10:42:\(String(format: "%02d", item % 60)) INFO    osxphotos | Exporting IMG_\(String(format: "%04d", 4300 + item)).HEIC (UUID-\(item).heic) (\(item)/631)"
}

@MainActor
private func makeStore(_ runner: DemoCommandRunner, backupFolder: String? = demoBackupFolder) async -> BackupStore {
    let store = BackupStore(commandRunner: runner, backupTarget: backupFolder, readDriveInfo: { _ in demoDrive })
    await store.reload()
    return store
}

/// Draws as the active window even though the test process is never the frontmost app.
private final class AlwaysActiveWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

private struct DemoNodeMissing: Error {}

@MainActor
private func demoNode(_ id: String, in store: BackupStore) throws -> ProgressNode {
    guard let node = store.nodesByID[id] else { throw DemoNodeMissing() }
    return node
}

@MainActor
private func letAppKitLayOut(forSeconds seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Lays the view out in a real window (with its toolbar) and saves the window's content as a PNG.
@MainActor
private func render(_ name: String, store: BackupStore, @ViewBuilder content: () -> some View) async throws {
    let folder = URL(fileURLWithPath: try #require(screenshotsFolder))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.appearance = NSAppearance(named: .aqua)
    NSApp.applicationIconImage = NSImage(contentsOf: appIconFile)
    NSApp.activate(ignoringOtherApps: true)

    let hostingController = NSHostingController(rootView: content().environment(store).environment(\.locale, Locale(identifier: "en_US")).environment(\.controlActiveState, .key).frame(width: windowSize.width, height: windowSize.height))
    hostingController.sceneBridgingOptions = [.toolbars, .title]
    let window = AlwaysActiveWindow(
        contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: windowSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentViewController = hostingController
    window.setContentSize(windowSize)
    window.makeKeyAndOrderFront(nil)
    // Let the view's own .task (it refreshes the counts on appear) finish, then let AppKit lay everything out.
    try await Task.sleep(for: .milliseconds(500))
    letAppKitLayOut(forSeconds: 0.5)

    let frameView = try #require(window.contentView?.superview)
    let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: folder.appending(path: "\(name).png"))
    window.close()
}

@MainActor
@Suite("README screenshots", .enabled(if: screenshotsFolder != nil, "set PHOTOS_BACKUP_SCREENSHOTS_FOLDER to render them"), .serialized)
struct ScreenshotTests {
    @Test func welcome() async throws {
        let store = await makeStore(DemoCommandRunner(progress: demoProgress), backupFolder: nil)
        try await render("1-welcome", store: store) { ContentView() }
    }

    @Test func overview() async throws {
        let store = await makeStore(DemoCommandRunner(progress: demoProgress))
        try await render("2-overview", store: store) { ContentView() }
    }

    @Test func years() async throws {
        let store = await makeStore(DemoCommandRunner(progress: demoProgress))
        try await render("3-years", store: store) { NavigationStack { PeriodScreen(nodeID: "library") } }
    }

    @Test func months() async throws {
        let store = await makeStore(DemoCommandRunner(progress: demoProgress))
        try await render("4-months", store: store) { NavigationStack { PeriodScreen(nodeID: "2016") } }
    }

    @Test func days() async throws {
        let store = await makeStore(DemoCommandRunner(progress: demoProgress))
        try await render("5-days", store: store) { NavigationStack { PeriodScreen(nodeID: "2016-12") } }
    }

    @Test func syncing() async throws {
        let store = await makeStore(DemoCommandRunner(progress: demoProgress, exportLines: demoExportLines, exportRunsUntilCancelled: true))
        let syncing = try #require(store.sync(try demoNode("2016-12", in: store)))
        while store.syncProgress?.currentItem != 214 { await Task.yield() }

        try await render("6-syncing", store: store) {
            NavigationStack { PeriodScreen(nodeID: "2016-12") }.safeAreaInset(edge: .bottom, spacing: 0) { SyncPanel() }
        }
        store.cancelSync()
        await syncing.value
    }

    @Test func finished() async throws {
        let store = await makeStore(DemoCommandRunner(progress: demoProgress, exportLines: ["Check passed"]))
        let syncDecember = try #require(store.sync(try demoNode("2016-12", in: store)))
        await syncDecember.value

        try await render("7-finished", store: store) {
            NavigationStack { PeriodScreen(nodeID: "2016") }.safeAreaInset(edge: .bottom, spacing: 0) { SyncPanel() }
        }
    }

    @Test func driveNotConnected() async throws {
        let unplugged = CommandResult(exitCode: 1, standardOutput: Data(), standardError: "Drive is not connected: /Volumes/Backup Drive")
        let store = await makeStore(DemoCommandRunner(progress: unplugged))
        try await render("8-drive-not-connected", store: store) { ContentView() }
    }
}
