import Foundation
import IOKit.ps

/// Battery state for energy-aware scheduling (#389).
public enum PowerState {
    public struct Reading: Sendable {
        public var onBattery: Bool
        public var percent: Int
    }

    /// nil on a desktop Mac (no internal battery).
    public static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else { return nil }
        for case let source as AnyObject in (list as NSArray) {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let onBattery = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            let percent = description[kIOPSCurrentCapacityKey] as? Int ?? 100
            return Reading(onBattery: onBattery, percent: percent)
        }
        return nil
    }

    /// On battery and below `percent`.
    public static func lowBattery(below percent: Int = 20) -> Bool {
        read().map { $0.onBattery && $0.percent < percent } ?? false
    }
}
