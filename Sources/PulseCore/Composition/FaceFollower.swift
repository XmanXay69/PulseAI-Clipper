import Foundation

/// A text layer (an emoji, a sticker) that follows the biggest face in a clip (#81): keyframes on the layer's
/// position every few frames, sitting just above the head, in canvas coordinates through the clip's crop.
public enum FaceFollower {
    /// Where the face is on the canvas at clip time `local`: the face box (source-normalized) mapped through
    /// the crop the clip shows at that moment, for a layer that fills the canvas.
    public static func canvasPoint(face: NormRect, clip: TimelineClip, local: Seconds) -> Vec2 {
        let crop = clip.transform.effectiveCrop(at: local)
        let x = (face.center.x - crop.x) / max(crop.width, 0.001)
        let y = (face.minY - crop.y) / max(crop.height, 0.001)
        return Vec2(x.clamped(0.05, 0.95), y.clamped(0.05, 0.95))
    }

    /// The emoji clip for `clip`'s whole span, or nil when the recording has no faces in that stretch.
    /// `lift` is how far above the top of the head the text sits (fraction of the canvas height).
    public static func pinned(_ text: String, to clip: TimelineClip, faces: [FaceSample], fontSize: Double = 120,
                              lift: Double = 0.09, step: Seconds = 0.25) -> TimelineClip? {
        let source = clip.sourceRange
        let samples = faces.filter { source.contains($0.time) && !$0.boxes.isEmpty }.sorted { $0.time < $1.time }
        guard !samples.isEmpty else { return nil }
        var element = TextElement(text: text, style: TextStyle(fontName: TextStyle.tiktokSans, fontSize: fontSize, weight: .black, textCase: .asTyped,
                                                              color: .white, strokeColor: .black, strokeWidth: 0, shadowOpacity: 0.35, shadowRadius: 8, shadowOffsetY: 4),
                                  animationIn: .pop, animationOut: .fadeIn, animationDuration: 0.2, maxWidth: 0.3)
        element.style.backgroundOpacity = 0
        var out = TimelineClip(name: "\(text) on face", content: .text(element), start: clip.start, sourceDuration: clip.sourceDuration, speed: clip.speed, aiGenerated: true)
        var last: Vec2?
        var t = source.start
        var i = 0
        while t <= source.end {
            // The sample nearest this moment.
            while i + 1 < samples.count && abs(samples[i + 1].time - t) <= abs(samples[i].time - t) { i += 1 }
            let sample = samples[i]
            guard abs(sample.time - t) < 1.5, let face = sample.boxes.max(by: { $0.area < $1.area }) else { t += step; continue }
            let local = (t - clip.sourceIn) / max(clip.speed, 0.01)
            var p = canvasPoint(face: face, clip: clip, local: local)
            p.y = (p.y - lift).clamped(0.04, 0.96)
            // A dead zone keeps the sticker still through small head movements.
            if let last, abs(last.x - p.x) < 0.015, abs(last.y - p.y) < 0.015 { t += step; continue }
            _ = out.transform.positionX.setKeyframe(at: max(0, local), value: p.x, interpolation: .easeInOut, aiGenerated: true)
            _ = out.transform.positionY.setKeyframe(at: max(0, local), value: p.y, interpolation: .easeInOut, aiGenerated: true)
            last = p
            t += step
        }
        guard out.transform.positionX.isAnimated else { return nil }
        return out
    }
}
