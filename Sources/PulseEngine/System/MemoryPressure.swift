import Foundation
import Darwin

/// Watches the system's memory-pressure signal and reports PULSE's own footprint (#377). Caches trim
/// themselves on a warning so the editor stays responsive instead of swapping. Events arrive on the main
/// queue, so the published level is safe to read from views.
public final class MemoryPressure: ObservableObject, @unchecked Sendable {
    public static let shared = MemoryPressure()

    public enum Level: String, Sendable {
        case normal, warning, critical

        public var displayName: String {
            switch self {
            case .normal: return "Normal"
            case .warning: return "Under pressure"
            case .critical: return "Critical"
            }
        }
    }

    @Published public private(set) var level: Level = .normal
    @Published public private(set) var lastWarning: Date?
    private var source: DispatchSourceMemoryPressure?
    /// Called on the main queue whenever the level leaves `.normal`.
    public var onPressure: ((Level) -> Void)?

    public func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let data = source.data
            let level: Level = data.contains(.critical) ? .critical : data.contains(.warning) ? .warning : .normal
            self.level = level
            if level != .normal {
                self.lastWarning = Date()
                PulseLog.warning("Memory pressure: \(level.rawValue) (PULSE is using \(Self.footprintDescription))")
                self.onPressure?(level)
            }
        }
        source.resume()
        self.source = source
    }

    /// Bytes this process has resident (the figure Activity Monitor calls "Memory"), nil if the kernel won't say.
    public nonisolated static func footprint() -> Int64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : nil
    }

    public nonisolated static var footprintDescription: String {
        guard let bytes = footprint() else { return "an unknown amount of memory" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
