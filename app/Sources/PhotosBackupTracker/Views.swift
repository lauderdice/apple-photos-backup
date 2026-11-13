import SwiftUI

// MARK: - Window

struct ContentView: View {
    @Environment(BackupStore.self) private var store

    var body: some View {
        NavigationStack {
            OverviewScreen()
                .navigationDestination(for: String.self) { nodeID in
                    PeriodScreen(nodeID: nodeID)
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SyncPanel()
        }
        .toolbar {
            ToolbarItemGroup {
                ChooseBackupFolderButton(label: "Backup Folder…")
                RefreshButton()
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .task { await store.reload() }
    }
}

// MARK: - Overview

struct OverviewScreen: View {
    @Environment(BackupStore.self) private var store

    var body: some View {
        Group {
            if store.backupTarget == nil {
                WelcomeView()
            } else if let loadError = store.loadError {
                ErrorView(message: loadError)
            } else if let library = store.libraryNode {
                ScrollView {
                    LibraryCard(library: library)
                        .padding(28)
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView("Comparing your Photos library with the backup…")
                    .controlSize(.large)
            }
        }
        .navigationTitle("Photos Backup")
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 28) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            VStack(spacing: 8) {
                Text("Back up your iCloud Photos")
                    .font(.largeTitle.bold())
                Text("Copy every photo and video to your own external drive, even the ones that are only in iCloud.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                WelcomeStep(number: 1, text: "Connect your external drive.")
                WelcomeStep(number: 2, text: "Choose a folder on it for the backup.")
                WelcomeStep(number: 3, text: "Pick a year, month or day and click Sync.")
            }
            ChooseBackupFolderButton(label: "Choose Backup Folder…")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WelcomeStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.tint))
            Text(text).font(.body)
        }
    }
}

struct ErrorView: View {
    @Environment(BackupStore.self) private var store
    let message: String

    var body: some View {
        let friendly = FriendlyError.describe(message)
        ContentUnavailableView {
            Label(friendly.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(friendly.advice)
        } actions: {
            HStack {
                Button("Try Again") { Task { await store.reload() } }
                    .buttonStyle(.borderedProminent)
                ChooseBackupFolderButton(label: "Choose Another Folder…")
            }
        }
    }
}

struct LibraryCard: View {
    @Environment(BackupStore.self) private var store
    let library: ProgressNode

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 28) {
                ProgressRing(fraction: library.syncedFraction, diameter: 132, lineWidth: 14)
                VStack(alignment: .leading, spacing: 8) {
                    Text(library.isFullyBackedUp ? "Everything is backed up" : "Photos Library")
                        .font(.title.bold())
                    Text("\(library.syncedItems, format: .number) of \(library.totalItems, format: .number) photos and videos backed up")
                        .font(.title3)
                    if !library.isFullyBackedUp {
                        Label("\(library.missingItems, format: .number) not backed up yet", systemImage: "icloud.and.arrow.down")
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }

            if let backupTarget = store.backupTarget {
                BackupDriveRow(backupFolder: backupTarget)
            }

            NavigationLink(value: library.id) {
                Label("Browse by Year", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 18).fill(.background.secondary))
    }
}

struct BackupDriveRow: View {
    @Environment(BackupStore.self) private var store
    let backupFolder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if let drive = store.backupDrive {
                    Text(drive.volumeName).font(.headline)
                    if let freeBytes = drive.freeBytes {
                        Text("\(freeBytes, format: .byteCount(style: .file)) free · \(backupFolder)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Backup drive not connected").font(.headline).foregroundStyle(.orange)
                    Text(backupFolder).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }
}

// MARK: - Years, months, days

struct PeriodScreen: View {
    @Environment(BackupStore.self) private var store
    let nodeID: String

    var body: some View {
        if let node = store.nodesByID[nodeID] {
            List {
                Section {
                    PeriodHeader(node: node)
                }
                Section(childrenHeading(for: node)) {
                    ForEach(node.children) { child in
                        if child.level == .day {
                            PeriodRow(node: child)
                        } else {
                            NavigationLink(value: child.id) {
                                PeriodRow(node: child)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle(node.title)
        } else {
            ContentUnavailableView("Nothing here anymore", systemImage: "questionmark.folder")
        }
    }

    private func childrenHeading(for node: ProgressNode) -> String {
        switch node.level {
        case .library: "Years"
        case .year: "Months"
        case .month, .day: "Days"
        }
    }
}

struct PeriodHeader: View {
    let node: ProgressNode

    var body: some View {
        HStack(spacing: 18) {
            ProgressRing(fraction: node.syncedFraction, diameter: 64, lineWidth: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(node.level == .library ? "All photos and videos" : node.title)
                    .font(.title2.bold())
                Text("\(node.syncedItems, format: .number) of \(node.totalItems, format: .number) backed up")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if node.canBeSynced {
                SyncButton(node: node, label: "Sync \(node.title)", isProminent: true)
            }
        }
        .padding(.vertical, 10)
        .alignmentGuide(.listRowSeparatorLeading) { header in header[.leading] }
    }
}

struct PeriodRow: View {
    let node: ProgressNode

    var body: some View {
        HStack(spacing: 14) {
            StatusIcon(node: node)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title).font(.headline)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressBar(fraction: node.syncedFraction)
                .frame(width: 120)
            if node.isFullyBackedUp {
                Text("Backed up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            } else {
                SyncButton(node: node, label: "Sync", isProminent: false)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .monospacedDigit()
        .padding(.vertical, 4)
        // Without this the list draws the separator under the last text in the row, i.e. under the Sync button.
        .alignmentGuide(.listRowSeparatorLeading) { row in row[.leading] }
    }

    private var subtitle: Text {
        node.isFullyBackedUp
            ? Text("\(node.totalItems, format: .number) photos and videos")
            : Text("\(node.syncedItems, format: .number) of \(node.totalItems, format: .number) backed up · \(node.missingItems, format: .number) missing")
    }
}

struct StatusIcon: View {
    let node: ProgressNode

    var body: some View {
        Group {
            if node.isFullyBackedUp {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if node.syncedItems > 0 {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(.orange)
            } else {
                Image(systemName: "icloud").foregroundStyle(.secondary)
            }
        }
        .font(.title2)
        .frame(width: 28)
        .help(node.isFullyBackedUp ? "Backed up" : (node.syncedItems > 0 ? "Partly backed up" : "Not backed up yet"))
    }
}

/// A thin bar: blue while in progress, green when complete.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(fraction >= 1 ? Color.green : Color.accentColor)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(.easeInOut, value: fraction)
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

struct ProgressRing: View {
    let fraction: Double
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(fraction >= 1 ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: diameter * 0.24, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut, value: fraction)
    }
}

// MARK: - Buttons

struct SyncButton: View {
    @Environment(BackupStore.self) private var store
    let node: ProgressNode
    let label: String
    let isProminent: Bool

    var body: some View {
        let button = Button {
            store.sync(node)
        } label: {
            Label(label, systemImage: "arrow.down.circle")
        }
        .disabled(store.isSyncing || node.isFullyBackedUp)
        .help(node.isFullyBackedUp ? "Everything here is already backed up" : "Copy \(node.missingItems.formatted()) missing items to the backup drive")

        if isProminent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered).controlSize(.small)
        }
    }
}

struct ChooseBackupFolderButton: View {
    @Environment(BackupStore.self) private var store
    @State private var isChoosingFolder = false
    let label: String

    var body: some View {
        Button(label) { isChoosingFolder = true }
            .disabled(store.isSyncing)
            .help("The folder on your external drive that holds the backup")
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                guard case .success(let folder) = result else { return }
                Task { await store.chooseBackupTarget(folder.path) }
            }
    }
}

struct RefreshButton: View {
    @Environment(BackupStore.self) private var store

    var body: some View {
        Button {
            Task { await store.reload() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .help("Count again (⌘R)")
        .disabled(store.isLoading || store.isSyncing || store.backupTarget == nil)
    }
}

// MARK: - Sync panel

struct SyncPanel: View {
    @Environment(BackupStore.self) private var store

    var body: some View {
        if store.isSyncing || store.lastSyncOutcome != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let activeSyncTitle = store.activeSyncTitle {
                    SyncingStatus(title: activeSyncTitle, progress: store.syncProgress)
                } else if let outcome = store.lastSyncOutcome, let title = store.lastSyncTitle {
                    SyncResult(title: title, outcome: outcome)
                }
                if !store.syncLog.isEmpty {
                    DisclosureGroup("Details") {
                        SyncLogView(lines: store.syncLog)
                    }
                    .font(.callout)
                }
            }
            .padding(16)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

struct SyncingStatus: View {
    @Environment(BackupStore.self) private var store
    let title: String
    let progress: SyncProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Backing up \(title)…").font(.headline)
                Spacer()
                Button("Cancel", role: .cancel) { store.cancelSync() }
                    .help("Stop after the current photo. Anything already copied stays on the drive.")
            }
            if let progress {
                ProgressBar(fraction: progress.fraction)
                Text("\(progress.currentItem, format: .number) of \(progress.totalItems, format: .number) · \(progress.currentFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                Text("Preparing… photos stored only in iCloud are downloaded first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SyncResult: View {
    @Environment(BackupStore.self) private var store
    let title: String
    let outcome: SyncOutcome

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.headline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button("Done") { store.dismissSyncResult() }
        }
    }

    private var symbol: String {
        switch outcome {
        case .finished: "checkmark.circle.fill"
        case .cancelled: "stop.circle.fill"
        case .failed, .couldNotStart: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch outcome {
        case .finished: .green
        case .cancelled: .secondary
        case .failed, .couldNotStart: .orange
        }
    }

    private var headline: String {
        switch outcome {
        case .finished: "\(title) is backed up"
        case .cancelled: "Backing up \(title) was cancelled"
        case .failed, .couldNotStart: "Backing up \(title) didn't finish"
        }
    }

    private var detail: String? {
        switch outcome {
        case .finished: nil
        case .cancelled: "Everything copied so far stays on the drive. Sync again to continue."
        case .failed(let exitCode): "Something went wrong (code \(exitCode)). Open Details to see what happened."
        case .couldNotStart(let reason): FriendlyError.describe(reason).advice
        }
    }
}

struct SyncLogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { lineNumber, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .id(lineNumber)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
            .onChange(of: lines.count) {
                scroller.scrollTo(lines.count - 1, anchor: .bottom)
            }
        }
    }
}
