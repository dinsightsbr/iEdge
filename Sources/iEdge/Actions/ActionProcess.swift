import Foundation

/// Outcome of a child process run by an action.
struct ActionProcessResult: Equatable {
    var status: Int32
    var timedOut = false
    /// Last lines of stderr (capped), for the failure toast.
    var errorOutput = ""
    /// Set when the process could not even start.
    var launchError: String?

    var succeeded: Bool { launchError == nil && !timedOut && status == 0 }

    /// One line for the toast: the last stderr line, else the reason.
    var failureDetail: String {
        if let launchError { return launchError }
        if timedOut { return "Tempo esgotado (\(Int(ActionProcess.defaultTimeout)) s)" }
        let lines = errorOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.last { !$0.isEmpty } ?? "Saiu com código \(status)"
    }
}

/// Runs an executable with an argument array (never through a shell string) off the main thread.
enum ActionProcess {
    static let defaultTimeout: TimeInterval = 30
    private static let maxErrorBytes = 8 * 1024

    /// `timeout` nil waits for as long as it takes (interactive screen captures).
    static func run(_ executable: URL, arguments: [String], timeout: TimeInterval? = defaultTimeout) async -> ActionProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(executable, arguments: arguments, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ executable: URL, arguments: [String], timeout: TimeInterval?) -> ActionProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        // Read stderr as it arrives: a background job of the command may keep the pipe open after
        // the process exits, so waiting for EOF could hang.
        let buffer = LockedBuffer(limit: maxErrorBytes)
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            buffer.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return ActionProcessResult(status: -1, launchError: error.localizedDescription)
        }

        let timedOut = LockedFlag()
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak process] in
                guard let process, process.isRunning else { return }
                timedOut.set()
                process.terminate()
            }
        }
        process.waitUntilExit()
        errorPipe.fileHandleForReading.readabilityHandler = nil

        return ActionProcessResult(
            status: process.terminationStatus,
            timedOut: timedOut.value,
            errorOutput: String(decoding: buffer.data, as: UTF8.self)
        )
    }
}

private final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        storage.append(data)
        if storage.count > limit { storage = storage.suffix(limit) }
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    func set() {
        lock.lock(); storage = true; lock.unlock()
    }

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
