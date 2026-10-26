import Foundation

/// What the Mac is playing sound through, as far as the mix is concerned (#283).
public enum AudioOutputKind: String, Sendable {
    case builtInSpeakers, headphoneJack, bluetooth, usb, hdmi, airPlay, other
}

/// A one-line monitoring note for Settings (#283): laptop speakers hide the low end and sibilance, Bluetooth
/// runs late against the picture, TVs flatter nothing. Nil when there's nothing to warn about.
public enum MixingAdvice {
    public static func line(outputName: String, kind: AudioOutputKind) -> String? {
        let name = outputName.trimmingCharacters(in: .whitespaces)
        let device = name.isEmpty ? "the built-in speakers" : name
        switch kind {
        case .builtInSpeakers:
            return "You’re listening through \(device). Laptop speakers hide bass, rumble and sibilance — check the mix on headphones before you export."
        case .bluetooth:
            return "\(device) is a Bluetooth device: sound runs 0.1–0.3 s behind the picture while you edit, so cuts can look early. Exports aren’t affected."
        case .hdmi:
            return "\(device) over HDMI: TV speakers and soundbars colour the mix — check it on headphones before you export."
        case .airPlay:
            return "\(device) over AirPlay runs about 2 s behind the picture — fine for listening, not for placing cuts."
        case .headphoneJack, .usb, .other:
            return nil
        }
    }
}
