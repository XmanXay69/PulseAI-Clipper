import AudioToolbox
import AVFoundation
import Foundation
import PulseCore

/// Neural noise removal with Apple's on-device voice isolation model (the `AUSoundIsolation` audio unit,
/// macOS 13+, runs on the Neural Engine/GPU). It keeps speech and removes everything else: keyboard
/// clicks, music, crowd, fans, traffic — the non-steady noise spectral subtraction can't touch.
/// Rendered offline, faster than real time, nothing leaves the Mac.
public enum VoiceIsolation {
    /// `kAudioUnitSubType_AUSoundIsolation` ('vois').
    static let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: 0x766F_6973,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)

    /// Whether this Mac has the voice isolation model.
    public static var isAvailable: Bool {
        var d = description
        return AudioComponentFindNext(nil, &d) != nil
    }

    static let chunk: AVAudioFrameCount = 4096

    /// Replaces each channel with its isolated voice, sample-aligned with the input.
    public static func process(_ channels: inout [[Float]], sampleRate: Double) throws {
        guard isAvailable else { throw EngineError.readerFailed("AI voice isolation isn't available on this Mac (needs macOS 13 or later)") }
        for c in channels.indices {
            channels[c] = try isolate(channels[c], sampleRate: sampleRate)
        }
    }

    /// The chain's hook (falls back to classic noise reduction when this returns false).
    public static func isolator(_ channels: inout [[Float]], sampleRate: Double) -> Bool {
        do {
            try process(&channels, sampleRate: sampleRate)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Why the last isolation fell back (for diagnostics).
    public static var lastError: String?

    static func isolate(_ samples: [Float], sampleRate: Double) throws -> [Float] {
        let length = samples.count
        guard length > 0 else { return samples }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw EngineError.readerFailed("unsupported sample rate \(sampleRate)")
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let effect = AVAudioUnitEffect(audioComponentDescription: description)
        engine.attach(player)
        engine.attach(effect)
        // Setting bus formats throws (instead of raising) if the model rejects this format.
        try effect.auAudioUnit.inputBusses[0].setFormat(format)
        try effect.auAudioUnit.outputBusses[0].setFormat(format)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk)
        // Fully wet: the Enhance chain mixes the original back in itself.
        for parameter in effect.auAudioUnit.parameterTree?.allParameters ?? [] {
            let name = (parameter.identifier + " " + parameter.displayName).lowercased()
            if name.contains("mix") || name.contains("wet") { parameter.value = parameter.maxValue }
        }
        try engine.start()
        defer { engine.stop() }

        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length))!
        input.frameLength = AVAudioFrameCount(length)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: length) }
        player.scheduleBuffer(input, completionHandler: nil)
        player.play()

        // Render past the end so the model's latency can be trimmed off the front.
        let reported = max(0, Int((effect.auAudioUnit.latency * sampleRate).rounded()))
        let maxLag = reported + Int(0.25 * sampleRate)
        let total = length + maxLag
        var output: [Float] = []
        output.reserveCapacity(total)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk) else {
            throw EngineError.readerFailed("couldn't allocate a render buffer")
        }
        var stalls = 0
        while output.count < total {
            let frames = AVAudioFrameCount(min(Int(chunk), total - output.count))
            switch try engine.renderOffline(frames, to: buffer) {
            case .success:
                output.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
                stalls = 0
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                stalls += 1
                if stalls > 100 { throw EngineError.readerFailed("voice isolation stalled") }
            case .error:
                throw EngineError.readerFailed("voice isolation render failed")
            @unknown default:
                throw EngineError.readerFailed("voice isolation render failed")
            }
        }
        // Align: the reported latency, confirmed (or corrected) by correlating with the input.
        var lag = min(reported, maxLag)
        let measured = SignalAlignment.delay(of: output, relativeTo: samples, maxLag: maxLag)
        if measured.correlation > 0.3 { lag = measured.lag }
        return Array(output[lag..<(lag + length)])
    }
}
