import CoreAudio
import Foundation
import PulseCore

/// What the Mac is playing sound through right now (#283): the default output device's name and kind, so
/// Settings can warn about laptop speakers and Bluetooth latency.
public enum AudioOutput {
    public struct Reading: Sendable {
        public var name: String
        public var kind: AudioOutputKind
    }

    public static func current() -> Reading? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { return nil }

        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)

        var transport: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &transportSize, &transport)

        var kind: AudioOutputKind
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            // The headphone jack is the same built-in device with another data source ('hdpn').
            var source: UInt32 = 0
            var sourceSize = UInt32(MemoryLayout<UInt32>.size)
            var sourceAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectGetPropertyData(device, &sourceAddress, 0, nil, &sourceSize, &source)
            kind = source == 0x6864706E /* 'hdpn' */ ? .headphoneJack : .builtInSpeakers
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: kind = .bluetooth
        case kAudioDeviceTransportTypeUSB: kind = .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: kind = .hdmi
        case kAudioDeviceTransportTypeAirPlay: kind = .airPlay
        default: kind = .other
        }
        let deviceName = name as String
        if kind == .builtInSpeakers, deviceName.localizedCaseInsensitiveContains("headphone") { kind = .headphoneJack }
        return Reading(name: deviceName, kind: kind)
    }

    /// The Settings footnote, or nil when the current output needs no warning.
    public static func advice() -> String? {
        guard let reading = current() else { return nil }
        return MixingAdvice.line(outputName: reading.name, kind: reading.kind)
    }
}
