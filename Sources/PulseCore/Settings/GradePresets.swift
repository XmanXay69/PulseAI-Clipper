import Foundation

/// A grade you saved from the inspector (#317).
public struct GradePreset: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var adjustments: ColorAdjustments

    public init(id: UUID = UUID(), name: String, adjustments: ColorAdjustments) {
        self.id = id
        self.name = name
        self.adjustments = adjustments
    }
}

extension Array where Element == GradePreset {
    /// Adds or replaces by name (case-insensitive).
    public mutating func save(_ name: String, adjustments: ColorAdjustments) {
        let key = name.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        if let i = firstIndex(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) {
            self[i].adjustments = adjustments
        } else {
            append(GradePreset(name: key, adjustments: adjustments))
        }
    }
}
