import Foundation

/// Localization scaffolding (#457): `L("Take the Tour")` looks the English key up in the app's string table
/// (Resources/<language>.lproj/Localizable.strings) and falls back to the key itself, so untranslated text
/// still reads correctly. New UI text goes through `L` so a translation only has to add a line.
enum L10n {
    /// The SwiftPM resource bundle, found next to the executable or inside the .app; the main bundle otherwise.
    static let bundle: Bundle = {
        let name = "PULSE_PulseApp.bundle"
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.bundleURL.deletingLastPathComponent()]
        for folder in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: folder.appendingPathComponent(name)) { return bundle }
        }
        return .main
    }()

    /// The language the strings come from ("en" until a translation is added).
    static var language: String { bundle.preferredLocalizations.first ?? "en" }

    static func text(_ key: String, comment: String = "") -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Shorthand for `L10n.text`.
func L(_ key: String) -> String { L10n.text(key) }
