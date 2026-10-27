import Foundation

/// A saved list of Ask PULSE requests (#479): record what you type, name it, play it back on any timeline.
public struct EditorMacro: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var steps: [String]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, steps: [String], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.steps = steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.createdAt = createdAt
    }

    /// One line: "cut the intro → tighten the pauses → add captions".
    public var summary: String { steps.joined(separator: " → ") }
}
