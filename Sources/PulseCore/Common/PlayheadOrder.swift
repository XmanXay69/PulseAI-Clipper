import Foundation

/// Orders background work by how soon playback will need it (#289).
public enum PlayheadOrder {
    /// `items` nearest the playhead first: anything under the playhead, then what comes next in play
    /// order, then what's behind it (which costs half again as much, since playback runs forward).
    /// Ties keep their original order.
    public static func sorted<T>(_ items: [T], around playhead: Seconds, range: (T) -> TimeRange) -> [T] {
        var scored: [(index: Int, item: T, cost: Seconds)] = []
        scored.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            let c: Seconds = cost(range(item), playhead: playhead)
            scored.append((index: index, item: item, cost: c))
        }
        scored.sort { a, b in
            if a.cost == b.cost { return a.index < b.index }
            return a.cost < b.cost
        }
        return scored.map { $0.item }
    }

    /// Seconds of playback before `range` is needed (0 when it's under the playhead).
    public static func cost(_ range: TimeRange, playhead: Seconds) -> Seconds {
        if range.contains(playhead) || (playhead >= range.start && playhead <= range.end) { return 0 }
        if range.start > playhead { return range.start - playhead }
        return (playhead - range.end) * 1.5
    }
}
