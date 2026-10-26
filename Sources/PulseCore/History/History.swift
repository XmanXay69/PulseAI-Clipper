import Foundation

/// Snapshot-based undo/redo. Every edit in PULSE mutates a value-type document, so storing
/// the prior state is cheap (copy-on-write arrays share storage) and makes *everything*
/// undoable: timeline edits, crops, captions, effects, text and audio changes, AI passes.
public struct History<State> {
    public struct Entry {
        public var state: State
        public var label: String
        public var coalesceKey: String?
        public var timestamp: Date
        /// What this snapshot costs to keep (#397), in whatever unit `cost` measures.
        public var cost: Int = 0
    }

    public private(set) var undoStack: [Entry] = []
    public private(set) var redoStack: [Entry] = []
    public var limit: Int
    /// Consecutive edits with the same coalesce key inside this window merge into one undo step
    /// (slider drags, nudging with arrow keys, typing).
    public var coalesceWindow: TimeInterval

    /// Oldest steps are dropped once the kept snapshots cost more than this (#397); 0 = no cap.
    public var maxCost: Int
    /// Measures a snapshot (roughly: clips + caption words + candidates). Called once per record.
    public var cost: ((State) -> Int)?

    public init(limit: Int = 300, coalesceWindow: TimeInterval = 1.0, maxCost: Int = 0, cost: ((State) -> Int)? = nil) {
        self.limit = limit
        self.coalesceWindow = coalesceWindow
        self.maxCost = maxCost
        self.cost = cost
    }

    /// The cost of every kept undo step.
    public var totalCost: Int { undoStack.reduce(0) { $0 + $1.cost } }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoLabel: String? { undoStack.last?.label }
    public var redoLabel: String? { redoStack.last?.label }

    /// Records `before` as the state to return to when the user undoes the edit named `label`.
    public mutating func record(_ before: State, label: String, coalesceKey: String? = nil, now: Date = Date()) {
        if let key = coalesceKey, let last = undoStack.last, last.coalesceKey == key,
           now.timeIntervalSince(last.timestamp) <= coalesceWindow {
            // Keep the original "before" state, refresh the timestamp so a continuous drag stays one step.
            undoStack[undoStack.count - 1].timestamp = now
            redoStack.removeAll()
            return
        }
        undoStack.append(Entry(state: before, label: label, coalesceKey: coalesceKey, timestamp: now, cost: cost?(before) ?? 0))
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        if maxCost > 0 {
            var total = totalCost
            while total > maxCost, undoStack.count > 1 {
                total -= undoStack.removeFirst().cost
            }
        }
        redoStack.removeAll()
    }

    /// Returns the state to restore, pushing `current` onto the redo stack.
    public mutating func undo(current: State) -> State? {
        guard let entry = undoStack.popLast() else { return nil }
        redoStack.append(Entry(state: current, label: entry.label, coalesceKey: nil, timestamp: Date()))
        return entry.state
    }

    /// Returns the state to re-apply, pushing `current` back onto the undo stack.
    public mutating func redo(current: State) -> State? {
        guard let entry = redoStack.popLast() else { return nil }
        undoStack.append(Entry(state: current, label: entry.label, coalesceKey: nil, timestamp: Date()))
        return entry.state
    }

    /// Ends any in-progress coalescing so the next edit starts a new undo step.
    public mutating func breakCoalescing() {
        guard !undoStack.isEmpty else { return }
        undoStack[undoStack.count - 1].coalesceKey = nil
    }

    public mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Labels for the History panel (oldest first).
    public var labels: [String] { undoStack.map(\.label) }
}
