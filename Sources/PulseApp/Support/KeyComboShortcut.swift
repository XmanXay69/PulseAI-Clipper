import PulseCore
import SwiftUI

extension KeyCombo {
    /// The SwiftUI shortcut for a menu item (#431); nil when the key isn't one SwiftUI can bind.
    var keyboardShortcut: KeyboardShortcut? {
        let equivalent: KeyEquivalent
        switch key {
        case "delete": equivalent = .delete
        case "return": equivalent = .return
        case "space": equivalent = .space
        case "escape": equivalent = .escape
        case "tab": equivalent = .tab
        case "up": equivalent = .upArrow
        case "down": equivalent = .downArrow
        case "left": equivalent = .leftArrow
        case "right": equivalent = .rightArrow
        default:
            guard let ch = key.first, key.count == 1 else { return nil }
            equivalent = KeyEquivalent(ch)
        }
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        return KeyboardShortcut(equivalent, modifiers: modifiers)
    }
}
