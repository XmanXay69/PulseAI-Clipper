import AppKit
import CoreText
import Foundation
import PulseCore

/// Fonts that ship with PULSE (Resources/Fonts): TikTok Sans, TikTok's own open-source typeface
/// (SIL Open Font License), so captions look native on short-form platforms.
public enum BundledFonts {
    public static let tiktokSans = "TikTok Sans"

    /// Registers the bundled fonts for this process (app UI and renderer). Safe to call repeatedly.
    @discardableResult
    public static func register() -> Bool { registered }

    private static let registered: Bool = {
        var ok = false
        for url in fontURLs {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                ok = true
            } else if let cf = error?.takeRetainedValue(), CFErrorGetCode(cf) == CTFontManagerError.alreadyRegistered.rawValue {
                ok = true
            }
        }
        return ok
    }()

    /// Inside PULSE.app, or next to the sources (swift run / tests).
    static var fontURLs: [URL] {
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL { dirs.append(resources.appendingPathComponent("Fonts")) }
        dirs.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Fonts"))
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let fonts = files.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
            if !fonts.isEmpty { return fonts }
        }
        return []
    }

    public static var isTikTokSansAvailable: Bool {
        register()
        return NSFontManager.shared.availableFontFamilies.contains(tiktokSans)
    }

    /// TikTok Sans at a weight, through its variable `wght` axis (300…900); nil if unavailable.
    public static func tiktokSans(size: CGFloat, weight: FontWeight, italic: Bool = false) -> NSFont? {
        guard isTikTokSansAvailable else { return nil }
        let value: Double
        switch weight {
        case .regular: value = 400
        case .medium: value = 500
        case .semibold: value = 600
        case .bold: value = 700
        case .heavy: value = 800
        case .black: value = 900
        }
        let wght = 0x7767_6874 // 'wght'
        let opsz = 0x6F70_737A // 'opsz': display optical size for big caption text
        let slnt = 0x736C_6E74 // 'slnt': its italic is a slant axis (0…-6)
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: tiktokSans,
            kCTFontVariationAttribute: [wght: value, opsz: min(36, max(12, Double(size))), slnt: italic ? -6.0 : 0.0],
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }
}
