import Foundation
import Testing
@testable import PhotosBackupTracker

/// A runner whose "CLI" is a shell script; the CLI arguments arrive as $1, $2, …
private func shellRunner(_ script: String) -> ProcessCommandRunner {
    ProcessCommandRunner(executable: URL(fileURLWithPath: "/bin/sh"), leadingArguments: ["-c", script, "sh"], workingDirectory: nil)
}

private actor LineCollector {
    private(set) var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
}

@Suite("Process command runner")
struct ProcessCommandRunnerTests {
    @Test func collectsStandardOutputStandardErrorAndExitCode() async throws {
        let result = try await shellRunner(#"echo "out:$1"; echo "err:$2" >&2; exit 7"#).run(["first", "second"])

        #expect(result.exitCode == 7)
        #expect(String(decoding: result.standardOutput, as: UTF8.self) == "out:first\n")
        #expect(result.standardError == "err:second\n")
    }

    @Test func largeOutputOnBothStreamsDoesNotDeadlock() async throws {
        let result = try await shellRunner("head -c 2000000 /dev/zero; head -c 2000000 /dev/zero >&2").run([])

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.count == 2_000_000)
        #expect(result.standardError.utf8.count == 2_000_000)
    }

    @Test func missingCLIFailsFastWithInstallInstructions() async {
        let runner = ProcessCommandRunner(executable: URL(fileURLWithPath: "/no/such/cli"), leadingArguments: [], workingDirectory: nil)

        await #expect(throws: CommandNotInstalled.self) { try await runner.run(["progress"]) }
        await #expect(throws: CommandNotInstalled.self) { try await runner.stream(["export"]) { _ in } }
        #expect(CommandNotInstalled(executable: runner.executable).localizedDescription.contains("make install"))
    }

    @Test func streamDeliversEveryLineInOrderIncludingStandardError() async throws {
        let collector = LineCollector()

        let exitCode = try await shellRunner(#"echo one; echo two >&2; echo; printf "last without newline""#)
            .stream([]) { line in await collector.append(line) }

        #expect(exitCode == 0)
        #expect(await collector.lines == ["one", "two", "", "last without newline"])
    }

    @Test func streamReturnsTheFailureExitCode() async throws {
        let exitCode = try await shellRunner("echo boom; exit 3").stream([]) { _ in }
        #expect(exitCode == 3)
    }

    @Test func streamHandlesUTF8Text() async throws {
        let collector = LineCollector()
        _ = try await shellRunner("echo 'Exportováno: Řím ☀️'").stream([]) { line in await collector.append(line) }
        #expect(await collector.lines == ["Exportováno: Řím ☀️"])
    }
}

@Suite("Backup configuration")
struct BackupConfigurationTests {
    @Test func defaultRunnerUsesTheCLIInstalledInApplicationSupport() {
        let runner = BackupConfiguration.makeCommandRunner(environment: [:])

        #expect(runner.executable.path.hasSuffix("/Library/Application Support/Photos Backup Tracker/cli/bin/photos-backup"))
        #expect(runner.executable.path.hasPrefix(NSHomeDirectory()))
        #expect(runner.leadingArguments.isEmpty)
        #expect(runner.workingDirectory?.path == NSHomeDirectory())
    }

    @Test func cliOverrideReplacesTheInstalledCLI() {
        let runner = BackupConfiguration.makeCommandRunner(environment: ["PHOTOS_BACKUP_TRACKER_CLI": "/tmp/fake-cli"])

        #expect(runner.executable.path == "/tmp/fake-cli")
        #expect(runner.leadingArguments.isEmpty)
    }

    @Test func noBackupFolderUntilTheUserPicksOne() throws {
        let defaults = try #require(UserDefaults(suiteName: "photos-backup-tracker-tests-\(UUID())"))
        #expect(BackupConfiguration.savedBackupTarget(environment: [:], defaults: defaults) == nil)
    }

    @Test func pickedBackupFolderIsRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "photos-backup-tracker-tests-\(UUID())"))
        defaults.set("/Volumes/Drive/Photos", forKey: BackupConfiguration.backupTargetDefaultsKey)

        #expect(BackupConfiguration.savedBackupTarget(environment: [:], defaults: defaults) == "/Volumes/Drive/Photos")
    }

    @Test func environmentOverridesTheRememberedFolder() throws {
        let defaults = try #require(UserDefaults(suiteName: "photos-backup-tracker-tests-\(UUID())"))
        defaults.set("/Volumes/Drive/Photos", forKey: BackupConfiguration.backupTargetDefaultsKey)

        let target = BackupConfiguration.savedBackupTarget(environment: ["PHOTOS_BACKUP_TRACKER_TARGET": "/Volumes/Test"], defaults: defaults)

        #expect(target == "/Volumes/Test")
    }
}
