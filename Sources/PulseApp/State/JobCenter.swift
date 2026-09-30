import Foundation
import PulseCore
import PulseEngine
import SwiftUI

/// A long-running background operation (analysis, transcription, proxies, exports…).
@MainActor
final class BackgroundJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case running
        case finished
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let title: String
    let kind: ActivityRecord.Kind
    let location: ProcessingLocation
    let startedAt = Date()
    @Published var detail: String = ""
    @Published var progress: Double = 0
    @Published var state: State = .running
    var task: Task<Void, Never>?
    private let cancelFlag = CancelFlag()

    init(title: String, kind: ActivityRecord.Kind, location: ProcessingLocation) {
        self.title = title
        self.kind = kind
        self.location = location
    }

    var isRunning: Bool { state == .running }
    var isCancelledCheck: @Sendable () -> Bool {
        let flag = cancelFlag
        return { flag.isSet }
    }

    func cancel() {
        cancelFlag.set()
        task?.cancel()
        state = .cancelled
    }
}

/// Thread-safe cancellation flag handed to engine code.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Tracks background jobs for the global progress indicator and the AI Activity feed.
@MainActor
final class JobCenter: ObservableObject {
    @Published private(set) var jobs: [BackgroundJob] = []
    var onFinished: ((BackgroundJob) -> Void)?

    var running: [BackgroundJob] { jobs.filter(\.isRunning) }

    /// Overall progress of running jobs (for the toolbar ring).
    var overallProgress: Double {
        let r = running
        guard !r.isEmpty else { return 1 }
        return r.map(\.progress).reduce(0, +) / Double(r.count)
    }

    @discardableResult
    func start(_ title: String, kind: ActivityRecord.Kind, location: ProcessingLocation = .local,
               operation: @escaping @MainActor (BackgroundJob) async throws -> Void) -> BackgroundJob {
        let job = BackgroundJob(title: title, kind: kind, location: location)
        jobs.insert(job, at: 0)
        if jobs.count > 40 { jobs.removeLast(jobs.count - 40) }
        job.task = Task { @MainActor [weak self] in
            do {
                try await operation(job)
                if job.state == .running {
                    job.progress = 1
                    job.state = .finished
                }
            } catch EngineError.cancelled {
                job.state = .cancelled
            } catch is CancellationError {
                job.state = .cancelled
            } catch {
                job.state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            self?.objectWillChange.send()
            self?.onFinished?(job)
        }
        objectWillChange.send()
        return job
    }

    func clearFinished() {
        jobs.removeAll { !$0.isRunning }
    }
}
