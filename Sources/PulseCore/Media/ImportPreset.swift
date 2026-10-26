import Foundation

/// Roles and sync behaviour applied to an import in one go (#25): the file names still get a say, but the
/// preset settles what kind of session this is instead of leaving every role to a guess.
public enum ImportPreset: String, Codable, CaseIterable, Sendable {
    /// Roles from the file names only.
    case auto
    /// One recording with everything in it: every video is a main recording, nothing is synced.
    case twitchVOD
    /// OBS / separate sources: the screen is gameplay, the camera is the webcam, audio files are the mic,
    /// and the batch is synced as one session.
    case obsRecording
    /// Talking only: audio files are microphones, a video is the camera, synced as one session.
    case podcast

    public var displayName: String {
        switch self {
        case .auto: return "Guess from names"
        case .twitchVOD: return "Twitch VOD"
        case .obsRecording: return "OBS recording"
        case .podcast: return "Podcast"
        }
    }

    public var detail: String {
        switch self {
        case .auto: return "Roles come from words in the file names (gameplay, webcam, mic…)"
        case .twitchVOD: return "One file with everything in it — each video is a main recording"
        case .obsRecording: return "Screen capture + camera + mic files, synced as one session"
        case .podcast: return "Microphone tracks (and a camera) synced as one session"
        }
    }

    /// Whether a batch imported under this preset is treated as one multi-source recording.
    public var syncsAsSession: Bool {
        switch self {
        case .auto: return false
        case .twitchVOD: return false
        case .obsRecording, .podcast: return true
        }
    }

    /// The role for one item; nil keeps what the file name suggested.
    public func role(for item: ImportPlan.Item, videoIndex: Int) -> MediaRole? {
        switch self {
        case .auto:
            return nil
        case .twitchVOD:
            switch item.kind {
            case .video: return .main
            case .audio: return item.role == .music || item.role == .soundEffect ? nil : .microphone
            case .image: return nil
            }
        case .obsRecording:
            switch item.kind {
            case .video:
                if item.role == .webcam || item.role == .camera { return .webcam }
                // The first unlabelled video is the screen; any later one is the camera.
                return videoIndex == 0 ? .gameplay : .webcam
            case .audio: return item.role == .music || item.role == .soundEffect ? nil : .microphone
            case .image: return nil
            }
        case .podcast:
            switch item.kind {
            case .video: return .camera
            case .audio: return item.role == .music || item.role == .soundEffect ? nil : .microphone
            case .image: return nil
            }
        }
    }
}

extension ImportPlan {
    /// The same plan with the preset's roles filled in.
    public func applying(_ preset: ImportPreset) -> ImportPlan {
        guard preset != .auto else { return self }
        var plan = self
        var videoIndex = 0
        for i in plan.items.indices {
            let item = plan.items[i]
            if let role = preset.role(for: item, videoIndex: videoIndex) { plan.items[i].role = role }
            if item.kind == .video { videoIndex += 1 }
        }
        plan.forcedSession = preset.syncsAsSession ? true : nil
        return plan
    }
}
