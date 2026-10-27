import Foundation

extension MulticamEditor {
    /// Picture-in-picture as a style (#328): the wide angle (the game) fills the frame the whole way through,
    /// and whoever is talking sits small in a corner, switching with the cuts.
    public static func pipTimeline(cuts: [MulticamCut], group: MulticamGroup, wideAngle: UUID? = nil, audioAssetID: UUID?,
                                   canvas: CanvasSettings, name: String, scale: Double = 0.28, corner: NormRect.Corner = .bottomRight) -> Timeline {
        var timeline = Timeline.empty(name: name, canvas: canvas)
        timeline.tracks[0].name = "V1 Game"
        timeline.tracks[1].name = "V2 Cam"
        let video = group.videoAngles
        let wide = wideAngle.flatMap { group.angle($0) } ?? video.first { $0.role == .gameplay } ?? video.first { !$0.hasAudio } ?? video.first
        let sorted = cuts.sorted { $0.range.start < $1.range.start }
        guard let wide, let first = sorted.first, let last = sorted.last else { return timeline }
        let origin = first.range.start
        let span = TimeRange(start: max(origin, wide.sessionRange.start), end: min(last.range.end, wide.sessionRange.end))
        if span.duration > Timeline.minimumClipDuration {
            var base = TimelineClip(name: wide.name, content: .media(assetID: wide.assetID), start: span.start - origin,
                                    sourceIn: wide.sourceTime(atSession: span.start), sourceDuration: span.duration, role: .gameplay)
            base.transform.fit = .fill
            timeline.tracks[0].clips.append(base)
        }
        let position = corner.center(inset: 0.04, size: scale, aspect: canvas.aspect)
        for cut in sorted where cut.range.duration > Timeline.minimumClipDuration {
            guard let angle = group.angle(cut.assetID), angle.assetID != wide.assetID else { continue }
            var cam = TimelineClip(name: angle.name, content: .media(assetID: angle.assetID), start: cut.range.start - origin,
                                   sourceIn: angle.sourceTime(atSession: cut.range.start), sourceDuration: cut.range.duration, role: .webcam)
            cam.transform.fit = .fill
            cam.transform.scale = AnimatedDouble(scale)
            cam.transform.positionX = AnimatedDouble(position.x)
            cam.transform.positionY = AnimatedDouble(position.y)
            cam.style = LayerStyle(mask: .roundedRectangle, cornerRadius: 0.12, borderWidth: 3, borderColor: .white, shadowRadius: 12, shadowOpacity: 0.5, shadowOffsetY: 4)
            cam.aiGenerated = true
            timeline.tracks[1].clips.append(cam)
        }
        if let audioID = audioAssetID ?? group.preferredAudioAngle?.assetID, let angle = group.angle(audioID) {
            let audioSpan = TimeRange(start: max(origin, angle.sessionRange.start), end: min(last.range.end, angle.sessionRange.end))
            if audioSpan.duration > Timeline.minimumClipDuration, let ai = timeline.tracks.firstIndex(where: { $0.kind == .audio }) {
                var audio = TimelineClip(name: "\(angle.name) audio", content: .media(assetID: angle.assetID), start: audioSpan.start - origin,
                                         sourceIn: angle.sourceTime(atSession: audioSpan.start), sourceDuration: audioSpan.duration, role: .microphone)
                audio.audio.normalize = true
                timeline.tracks[ai].clips.append(audio)
            }
        }
        timeline.notes = "Multicam edit · picture-in-picture · \(video.count) angles"
        return timeline
    }
}

extension NormRect {
    /// A corner of the canvas, for small layers that sit in one (#328).
    public enum Corner: String, CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight

        /// The centre of a layer `size` wide (as a fraction of the canvas width) set `inset` in from this
        /// corner, as normalized canvas coordinates; `aspect` = canvas width ÷ height.
        public func center(inset: Double, size: Double, aspect: Double) -> Vec2 {
            // A `fill` layer of a 16:9 camera at `size` of the width is size × (9/16) ÷ (1/aspect) tall.
            let width = size
            let height = size * (9.0 / 16.0) * aspect
            let x: Double, y: Double
            switch self {
            case .topLeft: x = inset + width / 2; y = inset + height / 2
            case .topRight: x = 1 - inset - width / 2; y = inset + height / 2
            case .bottomLeft: x = inset + width / 2; y = 1 - inset - height / 2
            case .bottomRight: x = 1 - inset - width / 2; y = 1 - inset - height / 2
            }
            return Vec2(x.clamped(0, 1), y.clamped(0, 1))
        }
    }
}
