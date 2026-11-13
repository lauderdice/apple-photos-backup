import Foundation

enum BackupConfiguration {
    /// The Python runtime app/build.sh embeds in the app, with the photos-backup CLI installed into it.
    static var bundledPython: URL {
        Bundle.main.resourceURL!.appending(path: "python/bin/python3")
    }

    /// UserDefaults key holding the backup folder the user picked.
    static let backupTargetDefaultsKey = "backupTargetPath"

    /// Replaces the bundled CLI with another executable (used by tests).
    static let cliOverrideVariable = "PHOTOS_BACKUP_TRACKER_CLI"
    /// Replaces the saved backup folder (used by tests).
    static let targetOverrideVariable = "PHOTOS_BACKUP_TRACKER_TARGET"

    static func makeCommandRunner(environment: [String: String] = ProcessInfo.processInfo.environment) -> ProcessCommandRunner {
        if let cliOverride = environment[cliOverrideVariable] {
            return ProcessCommandRunner(executable: URL(fileURLWithPath: cliOverride), leadingArguments: [])
        }
        // -I keeps the embedded Python isolated from anything installed on the Mac.
        return ProcessCommandRunner(executable: bundledPython, leadingArguments: ["-I", "-m", "photos_backup.cli"])
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
        "This copy of Photos Backup Tracker is incomplete (\(executable.lastPathComponent) is missing). Please download and install it again."
    }
}

/// Runs the `photos-backup` CLI with the given arguments.
protocol CommandRunning: Sendable {
    func run(_ arguments: [String]) async throws -> CommandResult
    /// Calls `onLine` for every printed line (stdout and stderr combined), in order, before returning the exit code.
    /// Cancelling the calling task stops the command.
    func stream(_ arguments: [String], onLine: @escaping @Sendable (String) async -> Void) async throws -> Int32
}

struct ProcessCommandRunner: CommandRunning {
    let executable: URL
    let leadingArguments: [String]

    /// The embedded runtime lives inside the signed app bundle, so it must never write bytecode caches there.
    static let childEnvironment = ProcessInfo.processInfo.environment.merging(["PYTHONDONTWRITEBYTECODE": "1"]) { _, forced in forced }

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

        return await withTaskCancellationHandler {
            var pendingLine = Data()
            do {
                for try await byte in pipe.fileHandleForReading.bytes {
                    if byte == UInt8(ascii: "\n") {
                        await onLine(String(decoding: pendingLine, as: UTF8.self))
                        pendingLine.removeAll(keepingCapacity: true)
                    } else {
                        pendingLine.append(byte)
                    }
                }
            } catch {
                // Reading stops when the task is cancelled; the process is being terminated meanwhile.
            }
            if !pendingLine.isEmpty {
                await onLine(String(decoding: pendingLine, as: UTF8.self))
            }
            return await exitCode.value
        } onCancel: {
            process.terminate()
        }
    }

    private func makeProcess(_ arguments: [String]) throws -> Process {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CommandNotInstalled(executable: executable)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = leadingArguments + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.environment = Self.childEnvironment
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
