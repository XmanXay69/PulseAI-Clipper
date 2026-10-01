import AVFoundation
import CoreMedia
import Foundation
import PulseCore
import ScreenCaptureKit

/// Something PULSE can record: a whole display or a single window.
public struct CaptureSource: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case display, window }
    public var id: String
    public var kind: Kind
    public var title: String
    public var subtitle: String
    /// Capture size in pixels.
    public var width: Int
    public var height: Int
    let displayID: CGDirectDisplayID?
    let windowID: CGWindowID?
}

/// A camera or microphone.
public struct CaptureDevice: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
}

public struct RecordingOptions: Sendable {
    public var source: CaptureSource
    public var captureSystemAudio: Bool
    public var cameraID: String?
    public var microphoneID: String?
    public var frameRate: Int
    public var showsCursor: Bool
    /// Keep PULSE's own windows out of a display recording.
    public var excludeSelf: Bool
    public var codec: VideoCodec
    public var outputDirectory: URL

    public init(source: CaptureSource, captureSystemAudio: Bool = true, cameraID: String? = nil, microphoneID: String? = nil,
                frameRate: Int = 60, showsCursor: Bool = true, excludeSelf: Bool = true, codec: VideoCodec = .hevc, outputDirectory: URL) {
        self.source = source
        self.captureSystemAudio = captureSystemAudio
        self.cameraID = cameraID
        self.microphoneID = microphoneID
        self.frameRate = frameRate
        self.showsCursor = showsCursor
        self.excludeSelf = excludeSelf
        self.codec = codec
        self.outputDirectory = outputDirectory
    }
}

/// Files written by one recording, with their start offsets on a shared clock (seconds after the
/// earliest file started) — ready to import as a synchronized session.
public struct RecordingResult: Sendable {
    public struct File: Sendable {
        public var url: URL
        public var role: MediaRole
        public var syncOffset: Seconds
    }
    public var files: [File]
    public var duration: Seconds
    public var warnings: [String]
}

public enum CaptureError: Error, LocalizedError {
    case screenPermission
    case cameraPermission
    case microphonePermission
    case sourceUnavailable
    case alreadyRecording
    case notRecording
    case writerFailed(String)
    case nothingRecorded

    public var errorDescription: String? {
        switch self {
        case .screenPermission:
            return "PULSE needs Screen Recording permission. Open System Settings → Privacy & Security → Screen & System Audio Recording, turn on PULSE, then relaunch it."
        case .cameraPermission:
            return "Camera access is off for PULSE. Enable it in System Settings → Privacy & Security → Camera."
        case .microphonePermission:
            return "Microphone access is off for PULSE. Enable it in System Settings → Privacy & Security → Microphone."
        case .sourceUnavailable:
            return "That display or window is no longer available. Pick another source."
        case .alreadyRecording:
            return "A recording is already running."
        case .notRecording:
            return "Nothing is being recorded."
        case .writerFailed(let detail):
            return "The recording couldn't be written: \(detail)"
        case .nothingRecorded:
            return "No frames were captured. If the screen stayed black, check the Screen Recording permission."
        }
    }
}

/// Seconds on the host clock (the clock ScreenCaptureKit and AVCapture timestamps use).
func hostSeconds() -> Seconds {
    CMClockGetTime(CMClockGetHostTimeClock()).seconds
}

/// Records a display/window (+ system audio) with ScreenCaptureKit and, optionally, a webcam and/or
/// microphone with AVCaptureSession — each into its own file, synced by host-clock start times.
public final class SessionRecorder: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var screen: ScreenCapture?
    private var camera: CameraCapture?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0

    public override init() {}

    public var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return screen != nil || camera != nil
    }

    // MARK: Discovery

    public static func sources() async throws -> [CaptureSource] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.screenPermission
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var list: [CaptureSource] = content.displays.enumerated().map { index, display in
            let scale = NSScreenScale.for(displayID: display.displayID)
            return CaptureSource(id: "display-\(display.displayID)", kind: .display, title: index == 0 ? "Main Display" : "Display \(index + 1)",
                                 subtitle: "\(display.width)×\(display.height) pt", width: Int(Double(display.width) * scale),
                                 height: Int(Double(display.height) * scale), displayID: display.displayID, windowID: nil)
        }
        let windows = content.windows.filter { w in
            w.isOnScreen && w.frame.width >= 200 && w.frame.height >= 150 && (w.title?.isEmpty == false)
                && w.owningApplication?.processID != ownPID && w.windowLayer == 0
        }
        list += windows.prefix(40).map { w in
            CaptureSource(id: "window-\(w.windowID)", kind: .window, title: w.title ?? "Window",
                          subtitle: w.owningApplication?.applicationName ?? "", width: Int(w.frame.width * 2), height: Int(w.frame.height * 2),
                          displayID: nil, windowID: w.windowID)
        }
        return list
    }

    public static func cameras() -> [CaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified)
            .devices.map { CaptureDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    public static func microphones() -> [CaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { CaptureDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func requestAccess(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }

    // MARK: Recording

    public func start(_ options: RecordingOptions) async throws {
        guard !isRecording else { throw CaptureError.alreadyRecording }
        try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
        let stamp = Self.stamp()
        if options.cameraID != nil, !(await Self.requestAccess(.video)) { throw CaptureError.cameraPermission }
        if options.microphoneID != nil, !(await Self.requestAccess(.audio)) { throw CaptureError.microphonePermission }

        let screenURL = options.outputDirectory.appendingPathComponent("Screen \(stamp).mov")
        let screen = try await ScreenCapture.make(options: options, url: screenURL)
        var camera: CameraCapture?
        if options.cameraID != nil || options.microphoneID != nil {
            let ext = options.cameraID != nil ? "mov" : "m4a"
            let name = options.cameraID != nil ? "Camera" : "Microphone"
            camera = try CameraCapture(cameraID: options.cameraID, microphoneID: options.microphoneID,
                                       url: options.outputDirectory.appendingPathComponent("\(name) \(stamp).\(ext)"))
        }
        // Start both as close together as possible; exact offsets come from host-clock timestamps.
        try await screen.start()
        do {
            try await camera?.start()
        } catch {
            _ = try? await screen.stop()
            throw error
        }
        lock.withLock {
            self.screen = screen
            self.camera = camera
            self.startedAt = Date()
            self.pausedAt = nil
            self.pausedTotal = 0
        }
    }

    /// Recorded time so far (paused time excluded).
    public var elapsed: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        guard let startedAt else { return 0 }
        let now = pausedAt ?? Date()
        return max(0, now.timeIntervalSince(startedAt) - pausedTotal)
    }

    public var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return pausedAt != nil
    }

    /// Pauses every file together; resuming continues the same files with no gap.
    public func pause() {
        lock.lock()
        guard startedAt != nil, pausedAt == nil else { lock.unlock(); return }
        pausedAt = Date()
        let screen = self.screen, camera = self.camera
        lock.unlock()
        screen?.pause()
        camera?.pause()
    }

    public func resume() {
        lock.lock()
        guard let pausedAt else { lock.unlock(); return }
        pausedTotal += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        let screen = self.screen, camera = self.camera
        lock.unlock()
        screen?.resume()
        camera?.resume()
    }

    public func stop() async throws -> RecordingResult {
        let (screen, camera) = lock.withLock { () -> (ScreenCapture?, CameraCapture?) in
            let taken = (self.screen, self.camera)
            self.screen = nil
            self.camera = nil
            self.startedAt = nil
            self.pausedAt = nil
            return taken
        }
        guard screen != nil || camera != nil else { throw CaptureError.notRecording }
        var warnings: [String] = []
        var raw: [(url: URL, role: MediaRole, hostStart: Seconds, duration: Seconds)] = []
        if let screen {
            do {
                let s = try await screen.stop()
                raw.append((s.url, .gameplay, s.hostStart, s.duration))
            } catch {
                warnings.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
        if let camera {
            do {
                let c = try await camera.stop()
                raw.append((c.url, camera.hasVideo ? .webcam : .microphone, c.hostStart, c.duration))
            } catch {
                warnings.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
        guard !raw.isEmpty else { throw CaptureError.nothingRecorded }
        let offsets = Self.syncOffsets(hostStarts: raw.map(\.hostStart))
        let files = zip(raw, offsets).map { RecordingResult.File(url: $0.url, role: $0.role, syncOffset: $1) }
        let duration = zip(raw, offsets).map { $0.duration + $1 }.max() ?? 0
        return RecordingResult(files: files, duration: duration, warnings: warnings)
    }

    /// Offsets on a shared clock whose zero is the earliest file start.
    public static func syncOffsets(hostStarts: [Seconds]) -> [Seconds] {
        guard let earliest = hostStarts.min() else { return [] }
        return hostStarts.map { $0 - earliest }
    }

    static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: date)
    }
}

enum NSScreenScale {
    static func `for`(displayID: CGDirectDisplayID) -> Double {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 2 }
        return Double(mode.pixelWidth) / Double(mode.width)
    }
}

// MARK: - Screen (ScreenCaptureKit → AVAssetWriter)

final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let url: URL
    private let stream: SCStream
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "app.pulse.capture.screen")
    private var firstVideoPTS: CMTime?
    private var lastVideoPTS: CMTime = .zero
    private var failure: Error?
    // Pause state (queue-confined). Samples after a resume are shifted back by the paused time,
    // so the file plays continuously.
    private var isPaused = false
    private var pauseStartedAt: CMTime?
    private var pausedTotal: CMTime = .zero

    private static func hostTime() -> CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    func pause() {
        queue.sync {
            guard !isPaused else { return }
            isPaused = true
            pauseStartedAt = Self.hostTime()
        }
    }

    func resume() {
        queue.sync {
            guard isPaused else { return }
            if let started = pauseStartedAt { pausedTotal = pausedTotal + (Self.hostTime() - started) }
            pauseStartedAt = nil
            isPaused = false
        }
    }

    /// Copy of `buffer` with its timestamps moved earlier by `offset`.
    static func retimed(_ buffer: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        guard offset != .zero else { return buffer }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for i in timing.indices {
            timing[i].presentationTimeStamp = timing[i].presentationTimeStamp - offset
            if timing[i].decodeTimeStamp.isValid { timing[i].decodeTimeStamp = timing[i].decodeTimeStamp - offset }
        }
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: count,
                                              sampleTimingArray: &timing, sampleBufferOut: &copy)
        return copy
    }

    private init(url: URL, stream: SCStream, writer: AVAssetWriter, videoInput: AVAssetWriterInput, audioInput: AVAssetWriterInput?) {
        self.url = url
        self.stream = stream
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
    }

    static func make(options: RecordingOptions, url: URL) async throws -> ScreenCapture {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw CaptureError.screenPermission
        }
        let filter: SCContentFilter
        var width = options.source.width
        var height = options.source.height
        switch options.source.kind {
        case .display:
            guard let display = content.displays.first(where: { $0.displayID == options.source.displayID }) else { throw CaptureError.sourceUnavailable }
            let pid = ProcessInfo.processInfo.processIdentifier
            let own = options.excludeSelf ? content.applications.filter { $0.processID == pid } : []
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let scale = NSScreenScale.for(displayID: display.displayID)
            width = Int(Double(display.width) * scale)
            height = Int(Double(display.height) * scale)
        case .window:
            guard let window = content.windows.first(where: { $0.windowID == options.source.windowID }) else { throw CaptureError.sourceUnavailable }
            filter = SCContentFilter(desktopIndependentWindow: window)
            width = Int(window.frame.width * 2)
            height = Int(window.frame.height * 2)
        }
        // Even dimensions, capped at 4K on the long side to keep files manageable.
        let longSide = max(width, height)
        if longSide > 3840 {
            let k = 3840.0 / Double(longSide)
            width = Int(Double(width) * k)
            height = Int(Double(height) * k)
        }
        width -= width % 2
        height -= height % 2

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, options.frameRate)))
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.showsCursor = options.showsCursor
        config.queueDepth = 6
        config.capturesAudio = options.captureSystemAudio
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let codec: AVVideoCodecType = options.codec == .h264 ? .h264 : .hevc
        let bitrate = Double(width * height) * Double(options.frameRate) * 0.08
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(min(max(bitrate, 6_000_000), 60_000_000)),
                AVVideoExpectedSourceFrameRateKey: options.frameRate,
                AVVideoMaxKeyFrameIntervalKey: options.frameRate * 2,
            ] as [String: Any],
        ])
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw CaptureError.writerFailed("video input rejected") }
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if options.captureSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }
        let placeholder = SCStream(filter: filter, configuration: config, delegate: nil)
        let capture = ScreenCapture(url: url, stream: placeholder, writer: writer, videoInput: videoInput, audioInput: audioInput)
        try placeholder.addStreamOutput(capture, type: .screen, sampleHandlerQueue: capture.queue)
        if audioInput != nil {
            try placeholder.addStreamOutput(capture, type: .audio, sampleHandlerQueue: capture.queue)
        }
        return capture
    }

    func start() async throws {
        guard writer.startWriting() else { throw CaptureError.writerFailed(writer.error?.localizedDescription ?? "couldn't start") }
        do {
            try await stream.startCapture()
        } catch {
            writer.cancelWriting()
            throw CaptureError.screenPermission
        }
    }

    func stop() async throws -> (url: URL, hostStart: Seconds, duration: Seconds) {
        // ScreenCaptureKit only delivers frames when the screen changes, so the recording ends when
        // Stop was pressed, not at the last changed frame.
        let stopHost = Self.hostTime()
        try? await stream.stopCapture()
        let (first, last, failure, paused): (CMTime?, CMTime, Error?, CMTime) = queue.sync {
            // A pause still running at Stop doesn't count either.
            let open = isPaused ? (pauseStartedAt.map { stopHost - $0 } ?? .zero) : .zero
            return (firstVideoPTS, lastVideoPTS, self.failure, pausedTotal + open)
        }
        let stopTime = stopHost - paused
        guard let first else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw failure ?? CaptureError.nothingRecorded
        }
        queue.sync {
            videoInput.markAsFinished()
            audioInput?.markAsFinished()
        }
        let end = CMTimeMaximum(last, stopTime)
        writer.endSession(atSourceTime: end)
        await writer.finishWriting()
        if writer.status == .failed { throw CaptureError.writerFailed(writer.error?.localizedDescription ?? "unknown error") }
        return (url, first.seconds, (end - first).seconds)
    }

    // SCStreamOutput (called on `queue`).
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, writer.status == .writing, !isPaused else { return }
        guard let sampleBuffer = Self.retimed(sampleBuffer, by: pausedTotal) else { return }
        switch type {
        case .screen:
            // Only complete frames carry pixels (idle/blank frames are status updates).
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            let pts = sampleBuffer.presentationTimeStamp
            if firstVideoPTS == nil {
                firstVideoPTS = pts
                writer.startSession(atSourceTime: pts)
            }
            if videoInput.isReadyForMoreMediaData, videoInput.append(sampleBuffer) {
                lastVideoPTS = pts
            }
        case .audio:
            guard let audioInput, let first = firstVideoPTS, sampleBuffer.presentationTimeStamp >= first else { return }
            if audioInput.isReadyForMoreMediaData { audioInput.append(sampleBuffer) }
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.failure = error }
    }
}

// MARK: - Camera / microphone (AVCaptureSession → movie or audio file)

final class CameraCapture: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let url: URL
    let hasVideo: Bool
    private let session = AVCaptureSession()
    private let output: AVCaptureFileOutput
    private let lock = NSLock()
    private var hostStart: Seconds?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuation: CheckedContinuation<Void, Error>?

    init(cameraID: String?, microphoneID: String?, url: URL) throws {
        self.url = url
        let video = cameraID != nil
        hasVideo = video
        if video {
            output = AVCaptureMovieFileOutput()
        } else {
            output = AVCaptureAudioFileOutput()
        }
        super.init()
        session.beginConfiguration()
        if let cameraID {
            guard let device = AVCaptureDevice(uniqueID: cameraID) else { throw CaptureError.sourceUnavailable }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CaptureError.sourceUnavailable }
            session.addInput(input)
            if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        }
        if let microphoneID {
            guard let device = AVCaptureDevice(uniqueID: microphoneID) else { throw CaptureError.sourceUnavailable }
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        }
        guard session.canAddOutput(output) else { throw CaptureError.writerFailed("capture output rejected") }
        session.addOutput(output)
        session.commitConfiguration()
    }

    func start() async throws {
        session.startRunning()
        try? FileManager.default.removeItem(at: url)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            startContinuation = continuation
            lock.unlock()
            if let movie = output as? AVCaptureMovieFileOutput {
                movie.startRecording(to: url, recordingDelegate: self)
            } else if let audio = output as? AVCaptureAudioFileOutput {
                audio.startRecording(to: url, outputFileType: .m4a, recordingDelegate: self)
            }
        }
    }

    func pause() {
        if output.isRecording && !output.isRecordingPaused { output.pauseRecording() }
    }

    func resume() {
        if output.isRecordingPaused { output.resumeRecording() }
    }

    func stop() async throws -> (url: URL, hostStart: Seconds, duration: Seconds) {
        let duration = output.recordedDuration.seconds
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            stopContinuation = continuation
            lock.unlock()
            output.stopRecording()
        }
        session.stopRunning()
        let start = lock.withLock { hostStart ?? hostSeconds() }
        return (url, start, duration)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        lock.lock()
        hostStart = hostSeconds()
        let c = startContinuation
        startContinuation = nil
        lock.unlock()
        c?.resume()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        lock.lock()
        let start = startContinuation, stop = stopContinuation
        startContinuation = nil
        stopContinuation = nil
        lock.unlock()
        // Recording "errors" after a normal stop still produce a usable file.
        let finishedOK = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        if let start {
            start.resume(throwing: CaptureError.writerFailed(error?.localizedDescription ?? "recording stopped"))
        }
        if finishedOK { stop?.resume() } else { stop?.resume(throwing: CaptureError.writerFailed(error?.localizedDescription ?? "unknown")) }
    }
}
