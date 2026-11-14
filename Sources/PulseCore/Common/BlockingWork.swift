import Foundation

/// Blocking work kept off Swift concurrency's cooperative threads.
///
/// The cooperative pool has about one thread per core. A blocking call parked on each of them (an
/// `AVAssetReader` waiting for its next buffer, a semaphore) leaves nothing to run the work those calls are
/// waiting for, and every `await` in the app stops with them: on a three-core machine, three waveforms read
/// at once were enough. Work passed to `run` uses a Dispatch thread instead, and a piece that stops reporting
/// progress is given up on, so its caller is released instead of waiting forever.
public enum BlockingWork {
    /// Says the work is still moving. Call `beat()` from inside long loops.
    public final class Heartbeat: @unchecked Sendable {
        private let lock = NSLock()
        private var last = Date()

        public init() {}

        public func beat() {
            lock.lock()
            last = Date()
            lock.unlock()
        }

        /// Seconds since the last beat.
        public var idle: TimeInterval {
            lock.lock()
            defer { lock.unlock() }
            return Date().timeIntervalSince(last)
        }
    }

    /// Resumes a continuation once, whichever of the work and its watch gets there first.
    final class Once<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?

        init(_ continuation: CheckedContinuation<T, Never>) {
            self.continuation = continuation
        }

        var isDone: Bool {
            lock.lock()
            defer { lock.unlock() }
            return continuation == nil
        }

        /// True when this call was the one that resumed it.
        @discardableResult
        func resume(_ value: T) -> Bool {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: value)
            return waiting != nil
        }
    }

    /// Runs `work` on a Dispatch thread and returns its value. When the work goes `stallLimit` seconds without
    /// a heartbeat, `fallback` is returned instead and the work is left to finish (or not) on its own thread.
    public static func run<T>(qos: DispatchQoS.QoSClass = .utility, stallLimit: TimeInterval = 30, fallback: T,
                              _ work: @escaping (Heartbeat) -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            let heartbeat = Heartbeat()
            let once = Once(continuation)
            DispatchQueue.global(qos: qos).async {
                once.resume(work(heartbeat))
            }
            let interval = max(0.05, min(1, stallLimit / 4))
            let watch = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            watch.schedule(deadline: .now() + interval, repeating: interval)
            watch.setEventHandler {
                if once.isDone {
                    watch.cancel()
                } else if heartbeat.idle > stallLimit {
                    once.resume(fallback)
                    watch.cancel()
                }
            }
            watch.resume()
        }
    }
}

/// Lets a few callers through at a time without holding a thread for the ones that wait.
public actor AsyncGate {
    private let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public func enter() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the place straight to the next caller in line, if there is one.
    public func leave() {
        if waiting.isEmpty {
            active = max(0, active - 1)
        } else {
            waiting.removeFirst().resume()
        }
    }
}
