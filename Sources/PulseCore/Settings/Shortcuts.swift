import Foundation

/// One keyboard shortcut (#431): a key plus modifiers, shown as "⌃⌥⇧⌘K" and parsed from that or from
/// "cmd+shift+k".
public struct KeyCombo: Codable, Hashable, Sendable {
    /// A single lower-case character, or one of the named keys: delete, return, space, escape, tab, up, down, left, right.
    public var key: String
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public static let namedKeys = ["delete", "return", "space", "escape", "tab", "up", "down", "left", "right"]

    public init(_ key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key.lowercased()
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    public var isValid: Bool {
        if KeyCombo.namedKeys.contains(key) { return true }
        return key.count == 1 && !key.first!.isWhitespace
    }

    /// Symbols in the Mac's menu order: ⌃ ⌥ ⇧ ⌘ then the key.
    public var display: String {
        var out = ""
        if control { out += "⌃" }
        if option { out += "⌥" }
        if shift { out += "⇧" }
        if command { out += "⌘" }
        switch key {
        case "delete": out += "⌫"
        case "return": out += "↩"
        case "space": out += "Space"
        case "escape": out += "⎋"
        case "tab": out += "⇥"
        case "up": out += "↑"
        case "down": out += "↓"
        case "left": out += "←"
        case "right": out += "→"
        default: out += key.uppercased()
        }
        return out
    }

    /// Reads "⌥⇧⌘K", "cmd+shift+k", "ctrl-alt-delete" and the like; nil when there's no key.
    public static func parse(_ text: String) -> KeyCombo? {
        var command = false, shift = false, option = false, control = false
        var rest = ""
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Symbol form.
        var symbols = Substring(trimmed)
        while let first = symbols.first, "⌃⌥⇧⌘".contains(first) {
            switch first {
            case "⌃": control = true
            case "⌥": option = true
            case "⇧": shift = true
            default: command = true
            }
            symbols = symbols.dropFirst()
        }
        if symbols.count != trimmed.count {
            rest = String(symbols)
        } else {
            // Word form: cmd+shift+k.
            let parts = trimmed.lowercased().split(whereSeparator: { "+-".contains($0) }).map { String($0).trimmingCharacters(in: .whitespaces) }
            for part in parts.dropLast() {
                switch part {
                case "cmd", "command", "⌘": command = true
                case "shift", "⇧": shift = true
                case "opt", "option", "alt", "⌥": option = true
                case "ctrl", "control", "⌃": control = true
                default: return nil
                }
            }
            rest = parts.last ?? ""
        }
        let key: String
        switch rest.lowercased() {
        case "⌫", "backspace", "del", "delete": key = "delete"
        case "↩", "enter", "return": key = "return"
        case "space", "␣": key = "space"
        case "⎋", "esc", "escape": key = "escape"
        case "⇥", "tab": key = "tab"
        case "↑", "up": key = "up"
        case "↓", "down": key = "down"
        case "←", "left": key = "left"
        case "→", "right": key = "right"
        default: key = rest.lowercased()
        }
        let combo = KeyCombo(key, command: command, shift: shift, option: option, control: control)
        return combo.isValid ? combo : nil
    }
}

/// The menu commands a shortcut can be changed for (#431).
public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case splitAtPlayhead, splitAllTracks, addTransition, copyAttributes, pasteAttributes, matchPreviousClip
    case loopInOut, exportInOut, exportSelectedClips, takeSnapshot, duplicate, detachAudio, freezeFrame
    case zoomIn, zoomOut, zoomToFit, markMoment, saveVersion, importMedia

    public var displayName: String {
        switch self {
        case .splitAtPlayhead: return "Split at Playhead"
        case .splitAllTracks: return "Split All Tracks at Playhead"
        case .addTransition: return "Add Transition"
        case .copyAttributes: return "Copy Attributes"
        case .pasteAttributes: return "Paste Attributes"
        case .matchPreviousClip: return "Match Previous Clip"
        case .loopInOut: return "Loop In → Out"
        case .exportInOut: return "Export In → Out"
        case .exportSelectedClips: return "Export Selected Clips"
        case .takeSnapshot: return "Take Snapshot"
        case .duplicate: return "Duplicate"
        case .detachAudio: return "Detach Audio"
        case .freezeFrame: return "Freeze Frame"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .zoomToFit: return "Zoom to Fit"
        case .markMoment: return "Mark Moment (Clip It)"
        case .saveVersion: return "Save Version"
        case .importMedia: return "Import Media"
        }
    }

    public var defaultCombo: KeyCombo {
        switch self {
        case .splitAtPlayhead: return KeyCombo("k")
        case .splitAllTracks: return KeyCombo("k", shift: true)
        case .addTransition: return KeyCombo("t")
        case .copyAttributes: return KeyCombo("c", option: true)
        case .pasteAttributes: return KeyCombo("v", option: true)
        case .matchPreviousClip: return KeyCombo("m", option: true)
        case .loopInOut: return KeyCombo("l", command: false, option: true)
        case .exportInOut: return KeyCombo("e", option: true)
        case .exportSelectedClips: return KeyCombo("e", shift: true, option: true)
        case .takeSnapshot: return KeyCombo("s", control: true)   // ⌥⌘S belongs to Save Version
        case .duplicate: return KeyCombo("d")
        case .detachAudio: return KeyCombo("d", shift: true)
        case .freezeFrame: return KeyCombo("f", command: false, shift: true)
        case .zoomIn: return KeyCombo("=")
        case .zoomOut: return KeyCombo("-")
        case .zoomToFit: return KeyCombo("z", command: false, shift: true)
        case .markMoment: return KeyCombo("m", shift: true)
        case .saveVersion: return KeyCombo("s", option: true)
        case .importMedia: return KeyCombo("i")
        }
    }
}

/// Custom shortcuts over the defaults, with conflict checks (#431).
public struct ShortcutMap: Codable, Hashable, Sendable {
    /// Action raw value → the combo chosen for it.
    public var custom: [String: KeyCombo] = [:]

    public init(custom: [String: KeyCombo] = [:]) { self.custom = custom }

    /// Shortcuts PULSE keeps for itself (the standard Mac ones), with what they do.
    public static let reserved: [(KeyCombo, String)] = [
        (KeyCombo("n"), "New Project"), (KeyCombo("o"), "Open Project"), (KeyCombo("s"), "Save"), (KeyCombo("w"), "Close Window"),
        (KeyCombo("w", shift: true), "Close Project"), (KeyCombo("q"), "Quit"), (KeyCombo(","), "Settings"), (KeyCombo("z"), "Undo"),
        (KeyCombo("z", shift: true), "Redo"), (KeyCombo("f"), "Search Everything"), (KeyCombo("a"), "Select All"), (KeyCombo("c"), "Copy"),
        (KeyCombo("v"), "Paste"), (KeyCombo("x"), "Cut"), (KeyCombo("e"), "Export"), (KeyCombo("i", shift: true), "Import from URL"),
        (KeyCombo("b", option: true), "Overnight Batch"), (KeyCombo("0", control: true), "Toggle Sidebar"),
    ]

    public func combo(for action: ShortcutAction) -> KeyCombo {
        custom[action.rawValue] ?? action.defaultCombo
    }

    public func isCustom(_ action: ShortcutAction) -> Bool { custom[action.rawValue] != nil }

    /// nil puts the default back.
    public mutating func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        if let combo, combo != action.defaultCombo { custom[action.rawValue] = combo } else { custom[action.rawValue] = nil }
    }

    /// Other actions already on this combo, plus a reserved Mac shortcut it would shadow.
    public func conflicts(for combo: KeyCombo, excluding action: ShortcutAction? = nil) -> [String] {
        var out: [String] = []
        for other in ShortcutAction.allCases where other != action && self.combo(for: other) == combo { out.append(other.displayName) }
        if let reserved = ShortcutMap.reserved.first(where: { $0.0 == combo }) { out.append(reserved.1) }
        return out
    }

    /// Every custom entry that collides with something.
    public var allConflicts: [(ShortcutAction, [String])] {
        ShortcutAction.allCases.compactMap { action in
            let found = conflicts(for: combo(for: action), excluding: action)
            return found.isEmpty ? nil : (action, found)
        }
    }
}
