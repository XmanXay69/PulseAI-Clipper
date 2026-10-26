import Foundation

/// Command-palette matching (#459): every query character in order, with points for a real substring, a
/// match at the start of a word, runs of adjacent characters and matches near the front.
public enum FuzzyMatch {
    /// nil when the query doesn't match; higher is better.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased().trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return 0 }
        let c = Array(candidate.lowercased())
        guard !c.isEmpty else { return nil }
        func isWordStart(_ i: Int) -> Bool { i == 0 || !(c[i - 1].isLetter || c[i - 1].isNumber) }
        // Substring first.
        if let range = candidate.lowercased().range(of: String(q)) {
            let at = candidate.lowercased().distance(from: candidate.startIndex, to: range.lowerBound)
            var score = 100 - min(at, 40) / 2
            if at == 0 { score += 40 } else if isWordStart(at) { score += 20 }
            return score
        }
        guard q.count >= 2 else { return nil }
        var i = 0
        var score = 50
        var previous = -2
        for ch in q {
            guard let found = c[i...].firstIndex(of: ch) else { return nil }
            if found == previous + 1 { score += 10 } else { score -= min(found - i, 12) }
            if isWordStart(found) { score += 8 }
            previous = found
            i = found + 1
        }
        return max(1, score)
    }

    /// `items` that match, best first; ties keep their order.
    public static func rank<T>(_ query: String, items: [T], text: (T) -> String) -> [T] {
        let scored = items.enumerated().compactMap { index, item -> (Int, Int, T)? in
            score(query, in: text(item)).map { ($0, index, item) }
        }
        return scored.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }.map(\.2)
    }
}
