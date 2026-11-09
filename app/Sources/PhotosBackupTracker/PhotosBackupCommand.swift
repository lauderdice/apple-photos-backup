import Foundation

enum BackupConfiguration {
    /// `make install` puts the app's own copy of the photos-backup CLI here.
    static let installedCLI = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Photos Backup Tracker/cli/bin/photos-backup")

    /// UserDefaults key holding the backup folder the user picked.
    static let backupTargetDefaultsKey = "backupTargetPath"

    /// Replaces the installed CLI with another executable (used by the end-to-end test).
    static let cliOverrideVariable = "PHOTOS_BACKUP_TRACKER_CLI"
    /// Replaces the saved backup folder (used by the end-to-end test).
    static let targetOverrideVariable = "PHOTOS_BACKUP_TRACKER_TARGET"

    static func makeCommandRunner(environment: [String: String] = ProcessInfo.processInfo.environment) -> ProcessCommandRunner {
        let executable = environment[cliOverrideVariable].map { URL(fileURLWithPath: $0) } ?? installedCLI
        return ProcessCommandRunner(
            executable: executable,
            leadingArguments: [],
            workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
        )
    }

    /// The backup folder to use at launch, or nil when the user hasn't picked one yet.
    static func savedBackupTarget(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> String? {
        environment[targetOverrideVariable] ?? defaults.string(forKey: backupTargetDefaultsKey)
    }
}

struct CommandResult: Equatable, Sendable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: String
}

struct CommandNotInstalled: Error, LocalizedError {
    let executable: URL
    var errorDescription: String? {
        "The photos-backup command line tool isn't installed at \(executable.path). Install it with `make install` from the project folder."
    }
}

/// Runs the `photos-backup` CLI with the given arguments.
protocol CommandRunning: Sendable {
    func run(_ arguments: [String]) async throws -> CommandResult
    /// Calls `onLine` for every printed line (stdout and stderr combined), in order, before returning the exit code.
    func stream(_ arguments: [String], onLine: @escaping @Sendable (String) async -> Void) async throws -> Int32
}

struct ProcessCommandRunner: CommandRunning {
    let executable: URL
    let leadingArguments: [String]
    let workingDirectory: URL?

    func run(_ arguments: [String]) async throws -> CommandResult {
        let process = try makeProcess(arguments)
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let exitCode = try launch(process)

        async let outputData = readToEnd(outputPipe)
        async let errorData = readToEnd(errorPipe)
        let (standardOutput, standardError) = await (outputData, errorData)
        return CommandResult(
            exitCode: await exitCode.value,
            standardOutput: standardOutput,
            standardError: String(decoding: standardError, as: UTF8.self)
        )
    }

    func stream(_ arguments: [String], onLine: @escaping @Sendable (String) async -> Void) async throws -> Int32 {
        let process = try makeProcess(arguments)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let exitCode = try launch(process)

        var pendingLine = Data()
        for try await byte in pipe.fileHandleForReading.bytes {
            if byte == UInt8(ascii: "\n") {
                await onLine(String(decoding: pendingLine, as: UTF8.self))
                pendingLine.removeAll(keepingCapacity: true)
            } else {
                pendingLine.append(byte)
            }
        }
        if !pendingLine.isEmpty {
            await onLine(String(decoding: pendingLine, as: UTF8.self))
        }
        return await exitCode.value
    }

    private func makeProcess(_ arguments: [String]) throws -> Process {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CommandNotInstalled(executable: executable)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = leadingArguments + arguments
        process.currentDirectoryURL = workingDirectory
        return process
    }

    /// Starts the process; the returned task finishes with its exit code.
    private func launch(_ process: Process) throws -> Task<Int32, Never> {
        let (terminations, continuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finishedProcess in
            continuation.yield(finishedProcess.terminationStatus)
            continuation.finish()
        }
        try process.run()
        return Task {
            for await exitCode in terminations { return exitCode }
            return -1
        }
    }

    private func readToEnd(_ pipe: Pipe) async -> Data {
        await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
    }
}
