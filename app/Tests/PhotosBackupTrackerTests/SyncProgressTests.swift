import Foundation
import Testing
@testable import PhotosBackupTracker

@Suite("Sync progress from log lines")
struct SyncProgressTests {
    @Test func readsTheCounterAndFileNameOfAnExportingLine() {
        let line = "2026-11-09 19:45:16,015 INFO    osxphotos | Exporting IMG_0561.PNG (A1C64566-2A24-47B1-BFF3-BD4CB6FF3D02.png) (42/630)"

        #expect(SyncProgress.parse(logLine: line) == SyncProgress(currentItem: 42, totalItems: 630, currentFileName: "IMG_0561.PNG"))
    }

    @Test func fileNamesWithSpacesAndBracketsSurvive() {
        let line = "INFO    osxphotos | Exporting Holiday (Rome) 1.HEIC (UUID.heic) (3/10)"

        #expect(SyncProgress.parse(logLine: line)?.currentFileName == "Holiday (Rome) 1.HEIC")
        #expect(SyncProgress.parse(logLine: line)?.currentItem == 3)
    }

    @Test(arguments: [
        "INFO    osxphotos | Exported IMG_0560.JPG to /Volumes/Drive/Photos Library/2016/12/08/IMG_0560.JPG",
        "INFO    osxphotos | Exporting 630 photos to /Volumes/Drive/Photos Library...",
        "INFO    Files already on the drive: 4",
        "",
    ])
    func linesWithoutACounterAreIgnored(line: String) {
        #expect(SyncProgress.parse(logLine: line) == nil)
    }

    @Test func fractionIsTheShareDone() {
        #expect(SyncProgress(currentItem: 42, totalItems: 84, currentFileName: "a").fraction == 0.5)
        #expect(SyncProgress(currentItem: 0, totalItems: 0, currentFileName: "a").fraction == 0)
    }
}

@Suite("Friendly error messages")
struct FriendlyErrorTests {
    @Test func unpluggedDrive() {
        let friendly = FriendlyError.describe("Drive is not connected: /Volumes/Backup")
        #expect(friendly.title == "Your backup drive isn't connected")
        #expect(friendly.advice.contains("Try Again"))
    }

    @Test func folderOnTheInternalDisk() {
        #expect(FriendlyError.describe("Target must be on an external drive under /Volumes: /Users/me").title == "Choose a folder on an external drive")
    }

    @Test func missingPhotosLibrary() {
        #expect(FriendlyError.describe("No System Photo Library is set; open Photos and choose one first.").title == "Couldn't find your Photos library")
    }

    @Test func unknownErrorsKeepTheOriginalMessage() {
        let friendly = FriendlyError.describe("Traceback: something odd")
        #expect(friendly.title == "Something went wrong")
        #expect(friendly.advice == "Traceback: something odd")
    }
}

@Suite("Backup drive info")
struct BackupDriveInfoTests {
    @Test func existingFolderReportsItsVolumeAndFreeSpace() throws {
        let folder = FileManager.default.temporaryDirectory.path
        let drive = try #require(BackupDriveInfo.read(backupFolder: folder))

        #expect(!drive.volumeName.isEmpty)
        #expect((drive.freeBytes ?? 0) > 0)
    }

    @Test func missingFolderMeansTheDriveIsNotConnected() {
        #expect(BackupDriveInfo.read(backupFolder: "/Volumes/Not Plugged In \(UUID())/Photos") == nil)
    }
}
