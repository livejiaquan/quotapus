import Darwin
import Foundation

/// Runs `ssh` with a script on stdin. Unlike `SystemProcessRunner`, this feeds stdin and caps stdout,
/// so it lives beside the SSH client. It keeps the same safety rules: both pipes drain on their own
/// queues (a chatty stderr can't deadlock stdout), the whole run has a deadline, and the blocking work
/// runs off Swift's cooperative pool so a slow device never stalls other refreshes.
enum SSHProcess {
    struct Output: Sendable {
        var status: Int32
        var stdout: Data
        var stderr: Data
    }

    enum Failure: Error, Equatable {
        case timedOut
        case oversized
    }

    /// Keeps only the start of stderr; error messages never need more.
    static let stderrLimit = 64 * 1024
    private static let drainGrace: TimeInterval = 5

    static func run(
        executable: String = "/usr/bin/ssh",
        arguments: [String],
        input: Data,
        timeout: TimeInterval,
        maxOutput: Int,
        environment: [String: String]? = nil
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "com.openusage.ssh-process", qos: .utility).async {
                do {
                    continuation.resume(returning: try runBlocking(
                        executable: executable, arguments: arguments, input: input,
                        timeout: timeout, maxOutput: maxOutput, environment: environment
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        executable: String, arguments: [String], input: Data, timeout: TimeInterval, maxOutput: Int,
        environment: [String: String]?
    ) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // nil inherits this app's environment, which is what ssh wants.
        if let environment { process.environment = environment }
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        // If ssh exits before reading its script (bad host, refused login), writing would raise
        // SIGPIPE and kill the whole app. With this flag the write fails with EPIPE instead.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let collected = Collected()
        let drained = DispatchGroup()
        let stopDraining = StopFlag()
        // Whatever happens below, a drain still blocked after its grace period (a descendant holding the
        // pipe open) stops and releases its handle instead of waiting on that descendant forever.
        defer { stopDraining.set() }
        drain(HandleBox(stdout.fileHandleForReading), limit: maxOutput, onOverflow: .closeEarly,
              label: "stdout", group: drained, stop: stopDraining) { collected.finishStdout($0, oversized: $1) }
        drain(HandleBox(stderr.fileHandleForReading), limit: stderrLimit, onOverflow: .discardRest,
              label: "stderr", group: drained, stop: stopDraining) { data, _ in collected.stderr = data }

        let exited = DispatchGroup()
        exited.enter()
        process.terminationHandler = { _ in exited.leave() }
        try process.run()

        let writer = HandleBox(stdin.fileHandleForWriting)
        DispatchQueue(label: "com.openusage.ssh-process.stdin", qos: .utility).async {
            // A failed write means ssh already exited; its exit status and stderr explain why.
            try? writer.handle.write(contentsOf: input)
            try? writer.handle.close()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            _ = drained.wait(timeout: .now() + drainGrace)
            throw Failure.timedOut
        }
        process.waitUntilExit()
        // A ControlPersist master or ProxyCommand child can inherit stderr and hold it open after ssh
        // exits, so the drains get a bounded grace period. stdout must still reach EOF to be trusted.
        _ = drained.wait(timeout: .now() + drainGrace)
        let result = collected.snapshot()
        if result.oversized { throw Failure.oversized }
        guard result.stdoutComplete else { throw Failure.timedOut }
        return Output(status: process.terminationStatus, stdout: result.stdout, stderr: result.stderr)
    }

    private enum Overflow { case closeEarly, discardRest }

    /// Reads a pipe to EOF on its own queue. Past `limit`, stdout closes its read end so ssh stops on
    /// EPIPE instead of streaming the rest; stderr keeps draining but stops storing. The read end is
    /// non-blocking and polled, so `stop` ends a drain that would otherwise wait on a descendant that
    /// inherited the pipe; the handle is closed either way so the descriptor doesn't leak.
    private static func drain(
        _ box: HandleBox, limit: Int, onOverflow: Overflow, label: String, group: DispatchGroup,
        stop: StopFlag, finish: @escaping @Sendable (Data, Bool) -> Void
    ) {
        group.enter()
        DispatchQueue(label: "com.openusage.ssh-process.\(label)", qos: .utility).async {
            let fd = box.handle.fileDescriptor
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            var data = Data()
            var overflowed = false
            var buffer = [UInt8](repeating: 0, count: 65_536)
            reading: while !stop.isSet {
                var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                guard poll(&pollFD, 1, 250) >= 0 || errno == EINTR else { break }
                let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if count == 0 { break }                       // EOF
                if count < 0 {
                    if errno == EAGAIN || errno == EINTR { continue }
                    break
                }
                let chunk = Data(buffer[0..<count])
                if data.count + chunk.count > limit {
                    overflowed = true
                    if onOverflow == .closeEarly { break reading }
                    data.append(chunk.prefix(max(0, limit - data.count)))
                    continue
                }
                data.append(chunk)
            }
            try? box.handle.close()
            finish(data, overflowed)
            group.leave()
        }
    }

    /// Set once the run returns, telling any drain still waiting to give up.
    private final class StopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }

    /// Results written once by each drain queue and read after the drains finish (or time out).
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var stdout = Data()
        private var stdoutComplete = false
        private var oversized = false
        private var _stderr = Data()

        var stderr: Data {
            get { lock.withLock { _stderr } }
            set { lock.withLock { _stderr = newValue } }
        }

        func finishStdout(_ data: Data, oversized: Bool) {
            lock.withLock {
                stdout = data
                self.oversized = oversized
                stdoutComplete = true
            }
        }

        func snapshot() -> (stdout: Data, stdoutComplete: Bool, oversized: Bool, stderr: Data) {
            lock.withLock { (stdout, stdoutComplete, oversized, _stderr) }
        }
    }

    /// Each handle is used by exactly one queue, so the unchecked conformance is sound.
    private final class HandleBox: @unchecked Sendable {
        let handle: FileHandle
        init(_ handle: FileHandle) { self.handle = handle }
    }
}
