import Foundation

/// A child process that stops when its job does: `terminate()` from a task's cancellation handler, or from the
/// poll `watch(_:)` runs against a job's cancel flag once a second. `wasTerminated` says the exit was ours.
final class ChildProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var _wasTerminated = false

    init() {}

    func set(_ process: Process) {
        lock.lock(); self.process = process; lock.unlock()
    }

    var wasTerminated: Bool {
        lock.lock(); defer { lock.unlock() }
        return _wasTerminated
    }

    /// Sends SIGTERM once; nothing when the process never ran or already exited.
    func terminate() {
        lock.lock()
        let p = process
        let running = p?.isRunning ?? false
        if running { _wasTerminated = true }
        lock.unlock()
        if running { p?.terminate() }
    }

    /// Checks `isCancelled` every second while the process runs and terminates it when the answer is yes.
    func watch(_ isCancelled: @escaping @Sendable () -> Bool) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let running = self.process?.isRunning ?? false
            self.lock.unlock()
            guard running else { return }
            if isCancelled() { self.terminate() } else { self.watch(isCancelled) }
        }
    }
}
