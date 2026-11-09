import SwiftUI

@main
struct PhotosBackupTrackerApp: App {
    @State private var store = BackupStore(
        commandRunner: BackupConfiguration.makeCommandRunner(),
        backupTarget: BackupConfiguration.savedBackupTarget(),
        saveBackupTarget: { path in UserDefaults.standard.set(path, forKey: BackupConfiguration.backupTargetDefaultsKey) }
    )

    var body: some Scene {
        Window("Photos Backup", id: "main") {
            ContentView()
                .environment(store)
        }
    }
}
