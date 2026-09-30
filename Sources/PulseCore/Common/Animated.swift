import Foundation

/// How a keyframe interpolates toward the NEXT keyframe.
public enum Interpolation: String, Codable, CaseIterable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case hold

    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In/Out"
        case .hold: return "Hold"
        }
    }

    /// Maps linear progress 0…1 to eased progress.
    public func apply(_ t: Double) -> Double {
        let x = t.clamped(0, 1)
        switch self {
        case .linear: return x
        case .easeIn: return x * x * x
        case .easeOut:
            let inv = 1 - x
            return 1 - inv * inv * inv
        case .easeInOut:
            return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        case .hold: return 0
        }
    }
}

/// A single keyframe. `time` is relative to the owning clip's start on the timeline.
public struct ValueKeyframe: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var time: Seconds
    public var value: Double
    public var interpolation: Interpolation
    /// True when created by an AI pass (auto punch-in, reframing…). Shown with an AI badge.
    public var aiGenerated: Bool

    public init(id: UUID = UUID(), time: Seconds, value: Double, interpolation: Interpolation = .easeInOut, aiGenerated: Bool = false) {
        self.id = id
        self.time = time
        self.value = value
        self.interpolation = interpolation
        self.aiGenerated = aiGenerated
    }
}

/// A scalar property that is either constant (`value`) or animated by keyframes.
public struct AnimatedDouble: Codable, Hashable, Sendable {
    /// Constant value used when there are no keyframes.
    public var value: Double
    /// Keyframes sorted by time.
    public private(set) var keyframes: [ValueKeyframe]

    public init(_ value: Double, keyframes: [ValueKeyframe] = []) {
        self.value = value
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    public var isAnimated: Bool { !keyframes.isEmpty }
    public var hasAIKeyframes: Bool { keyframes.contains { $0.aiGenerated } }

    /// Evaluates the property at a clip-relative time.
    public func value(at time: Seconds) -> Double {
        guard let first = keyframes.first, let last = keyframes.last else { return value }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        // Binary search for the segment containing `time`.
        var lo = 0
        var hi = keyframes.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if keyframes[mid].time <= time { lo = mid } else { hi = mid }
        }
        let a = keyframes[lo]
        let b = keyframes[hi]
        let span = b.time - a.time
        guard span > TimeRange.epsilon else { return b.value }
        if a.interpolation == .hold { return a.value }
        let progress = a.interpolation.apply((time - a.time) / span)
        return a.value + (b.value - a.value) * progress
    }

    /// Adds or replaces a keyframe at (approximately) `time`.
    @discardableResult
    public mutating func setKeyframe(at time: Seconds, value: Double, interpolation: Interpolation = .easeInOut, aiGenerated: Bool = false, tolerance: Seconds = 1.0 / 240.0) -> UUID {
        if let idx = keyframes.firstIndex(where: { abs($0.time - time) <= tolerance }) {
            keyframes[idx].value = value
            keyframes[idx].interpolation = interpolation
            keyframes[idx].aiGenerated = aiGenerated && keyframes[idx].aiGenerated
            return keyframes[idx].id
        }
        let kf = ValueKeyframe(time: time, value: value, interpolation: interpolation, aiGenerated: aiGenerated)
        keyframes.append(kf)
        keyframes.sort { $0.time < $1.time }
        return kf.id
    }

    public mutating func removeKeyframe(id: UUID) {
        keyframes.removeAll { $0.id == id }
    }

    public mutating func removeAllKeyframes(keepingValueAt time: Seconds? = nil) {
        if let time { value = value(at: time) }
        keyframes.removeAll()
    }

    public mutating func removeAIKeyframes() {
        keyframes.removeAll { $0.aiGenerated }
    }

    public mutating func moveKeyframe(id: UUID, to time: Seconds) {
        guard let idx = keyframes.firstIndex(where: { $0.id == id }) else { return }
        keyframes[idx].time = time
        keyframes.sort { $0.time < $1.time }
    }

    /// Shifts all keyframes (used when trimming a clip's head so animation stays locked to content).
    public mutating func shiftKeyframes(by delta: Seconds) {
        guard delta != 0 else { return }
        for i in keyframes.indices { keyframes[i].time += delta }
    }

    /// Keeps only keyframes inside `range` (clip-relative), used after splitting.
    public mutating func retainKeyframes(in range: TimeRange, rebasingTo newOrigin: Seconds) {
        let boundaryValueStart = value(at: range.start)
        let hadKeyframes = isAnimated
        keyframes = keyframes
            .filter { $0.time >= range.start - TimeRange.epsilon && $0.time <= range.end + TimeRange.epsilon }
            .map { var k = $0; k.time -= newOrigin; return k }
        if hadKeyframes && keyframes.isEmpty {
            value = boundaryValueStart
        }
    }
}

// MARK: - Resilient decoding helpers

extension KeyedDecodingContainer {
    /// Decodes a value if present, otherwise returns `defaultValue`. Also falls back when the
    /// stored value is malformed so that older/newer project files still open.
    public func decode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T) -> T {
        if let value = try? decodeIfPresent(type, forKey: key) {
            return value
        }
        return defaultValue()
    }
}
