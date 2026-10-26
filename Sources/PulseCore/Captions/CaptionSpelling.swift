import Foundation

/// Which caption words are worth a spell check (#242): not numbers, not GG / LOL / HP, not emoji, not names
/// and game words you taught PULSE. The dictionary lookup itself is the system spell checker (app side).
public enum CaptionSpelling {
    public static func checkable(_ words: [CaptionWord], known: [String]) -> [CaptionWord] {
        let vocabulary = Set(known.map { normalize($0) }.filter { !$0.isEmpty })
        return words.filter { w in
            guard !w.isHidden else { return false }
            let core = normalize(w.text)
            guard core.count >= 3, core.allSatisfy({ $0.isLetter || $0 == "\u{2019}" || $0 == "'" || $0 == "-" }) else { return false }
            let letters = w.text.filter(\.isLetter)
            if letters.count <= 4, letters == letters.uppercased() { return false }   // GG, LOL, HP, AFK
            if vocabulary.contains(core.lowercased()) { return false }
            return true
        }
    }

    /// Lowercase, surrounding punctuation stripped.
    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces).union(.symbols)).lowercased()
    }
}
