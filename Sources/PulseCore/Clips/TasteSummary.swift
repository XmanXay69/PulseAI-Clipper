import Foundation

extension TasteProfile {
    /// What PULSE has learned from your 👍 / 👎, in plain lines (#51). Empty until you've rated something.
    public var summaryLines: [String] {
        guard !isEmpty else { return [] }
        var lines = ["\(likes) 👍 · \(dislikes) 👎 · \(Int((confidence * 100).rounded())) % sure of your taste"]
        func describe(_ weights: [String: Double], names: (String) -> String) -> (up: [String], down: [String]) {
            let sorted = weights.filter { abs($0.value) >= 0.05 }.sorted { abs($0.value) > abs($1.value) }
            let up = sorted.filter { $0.value > 0 }.prefix(3).map { "\(names($0.key)) (+\(Int(($0.value * 100).rounded())) %)" }
            let down = sorted.filter { $0.value < 0 }.prefix(3).map { "\(names($0.key)) (−\(Int((abs($0.value) * 100).rounded())) %)" }
            return (up, down)
        }
        let dims = describe(dimensionWeights) { $0.lowercased() }
        let tags = describe(tagWeights) { ClipTag(rawValue: $0)?.displayName.lowercased() ?? $0 }
        if !dims.up.isEmpty || !tags.up.isEmpty { lines.append("Leans toward: " + (dims.up + tags.up).joined(separator: ", ")) }
        if !dims.down.isEmpty || !tags.down.isEmpty { lines.append("Cares less about: " + (dims.down + tags.down).joined(separator: ", ")) }
        if abs(bias) >= 0.05 { lines.append(bias > 0 ? "Generally likes what PULSE picks" : "Generally stricter than PULSE") }
        return lines
    }
}
