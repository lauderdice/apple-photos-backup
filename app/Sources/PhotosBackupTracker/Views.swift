import SwiftUI

struct ContentView: View {
    @Environment(BackupStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                libraryOverview
                    .navigationTitle("Photos Backup")
                    .navigationSubtitle(store.backupTarget ?? "No backup folder chosen")
                    .navigationDestination(for: String.self) { nodeID in
                        NodeChildrenView(nodeID: nodeID)
                    }
                    .toolbar {
                        ChooseBackupFolderButton(label: "Backup Folder…")
                        RefreshButton()
                    }
            }
            SyncPanel()
        }
        .frame(minWidth: 720, minHeight: 520)
        .task { await store.reload() }
    }

    @ViewBuilder private var libraryOverview: some View {
        if store.backupTarget == nil {
            ContentUnavailableView {
                Label("Choose your backup folder", systemImage: "externaldrive")
            } description: {
                Text("Pick a folder on your external drive. Photos are exported there into Photos Library/YYYY/MM/DD.")
            } actions: {
                ChooseBackupFolderButton(label: "Choose Backup Folder…")
                    .buttonStyle(.borderedProminent)
            }
        } else if let library = store.libraryNode {
            List {
                NavigationLink(value: library.id) {
                    ProgressRow(node: library)
                }
            }
        } else if let loadError = store.loadError {
            ContentUnavailableView {
                Label("Couldn't read the backup status", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError).font(.callout.monospaced())
            } actions: {
                Button("Try again") { Task { await store.reload() } }
            }
        } else {
            ProgressView("Comparing the Photos library with the drive…")
        }
    }
}

struct NodeChildrenView: View {
    @Environment(BackupStore.self) private var store
    let nodeID: String

    var body: some View {
        if let node = store.nodesByID[nodeID] {
            List(node.children) { child in
                if child.level == .day {
                    ProgressRow(node: child)
                } else {
                    NavigationLink(value: child.id) {
                        ProgressRow(node: child)
                    }
                }
            }
            .navigationTitle(node.title)
            .toolbar {
                if node.canBeSynced {
                    SyncButton(node: node, label: "Sync \(node.title)")
                }
                RefreshButton()
            }
        } else {
            ContentUnavailableView("Nothing here anymore", systemImage: "questionmark.folder")
        }
    }
}

struct ProgressRow: View {
    let node: ProgressNode

    var body: some View {
        HStack(spacing: 16) {
            Text(node.title)
                .font(node.level == .library ? .title2.bold() : .headline)
            Spacer()
            Label("\(node.syncedItems.formatted()) synced", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Label("\(node.missingItems.formatted()) missing", systemImage: "icloud.and.arrow.down")
                .foregroundStyle(node.missingItems > 0 ? .orange : .secondary)
            ProgressView(value: node.syncedFraction)
                .frame(width: 90)
            if node.canBeSynced {
                SyncButton(node: node, label: "Sync")
            }
        }
        .monospacedDigit()
        .padding(.vertical, node.level == .library ? 8 : 2)
    }
}

struct SyncButton: View {
    @Environment(BackupStore.self) private var store
    let node: ProgressNode
    let label: String

    var body: some View {
        Button(label) { store.sync(node) }
            .buttonStyle(.borderless)
            .disabled(store.isSyncing || node.missingItems == 0)
            .help(node.missingItems == 0 ? "Everything here is already on the drive" : "Export \(node.firstDay) to \(node.lastDay) to the drive")
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
        .disabled(store.isLoading || store.isSyncing || store.backupTarget == nil)
    }
}

struct SyncPanel: View {
    @Environment(BackupStore.self) private var store

    var body: some View {
        if store.isSyncing || store.lastSyncSummary != nil || store.isLoading {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let activeSyncTitle = store.activeSyncTitle {
                        ProgressView().controlSize(.small)
                        Text("Syncing \(activeSyncTitle)…")
                    } else if store.isLoading {
                        ProgressView().controlSize(.small)
                        Text("Refreshing counts…")
                    } else if let lastSyncSummary = store.lastSyncSummary {
                        Text(lastSyncSummary)
                    }
                    Spacer()
                }
                .font(.callout.bold())
                if !store.syncLog.isEmpty {
                    SyncLogView(lines: store.syncLog)
                }
            }
            .padding(10)
            .background(.bar)
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
            .frame(height: 160)
            .onChange(of: lines.count) {
                scroller.scrollTo(lines.count - 1, anchor: .bottom)
            }
        }
    }
}
