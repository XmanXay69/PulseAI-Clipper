import Foundation

/// Several multicam angles on screen at once.
public enum MulticamGridLayout: String, Codable, CaseIterable, Sendable {
    /// One angle, full frame (no grid).
    case single
    /// Two angles: stacked on vertical canvases, side by side on landscape.
    case twoUp
    /// One large + two small.
    case threeUp
    /// 2 × 2.
    case quad
    /// One featured angle with a strip of up to three small ones.
    case featured

    public var displayName: String {
        switch self {
        case .single: return "Single"
        case .twoUp: return "2-Up"
        case .threeUp: return "3-Up"
        case .quad: return "2 × 2"
        case .featured: return "Featured"
        }
    }

    public var symbolName: String {
        switch self {
        case .single: return "rectangle"
        case .twoUp: return "rectangle.split.2x1"
        case .threeUp: return "rectangle.split.1x2"
        case .quad: return "rectangle.split.2x2"
        case .featured: return "rectangle.bottomthird.inset.filled"
        }
    }

    /// Maximum angles the layout shows.
    public var capacity: Int {
        switch self {
        case .single: return 1
        case .twoUp: return 2
        case .threeUp: return 3
        case .quad, .featured: return 4
        }
    }

    /// Sensible layout for a number of angles.
    public static func automatic(for count: Int) -> MulticamGridLayout {
        switch count {
        case ..<2: return .single
        case 2: return .twoUp
        case 3: return .threeUp
        default: return .quad
        }
    }

    /// Normalized canvas rects for `count` angles (first = most prominent), separated by `gap`
    /// (fraction of the canvas width).
    public func slots(count: Int, canvas: CanvasSettings, gap: Double = 0.008) -> [NormRect] {
        let n = max(1, min(count, capacity))
        let portrait = canvas.aspect < 1
        var rects: [NormRect]
        switch self {
        case .single:
            rects = [.full]
        case .twoUp:
            rects = portrait
                ? [NormRect(x: 0, y: 0, width: 1, height: 0.5), NormRect(x: 0, y: 0.5, width: 1, height: 0.5)]
                : [NormRect(x: 0, y: 0, width: 0.5, height: 1), NormRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case .threeUp:
            rects = portrait
                ? [NormRect(x: 0, y: 0, width: 1, height: 0.5), NormRect(x: 0, y: 0.5, width: 0.5, height: 0.5), NormRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
                : [NormRect(x: 0, y: 0, width: 0.5, height: 1), NormRect(x: 0.5, y: 0, width: 0.5, height: 0.5), NormRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
        case .quad:
            rects = [NormRect(x: 0, y: 0, width: 0.5, height: 0.5), NormRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                     NormRect(x: 0, y: 0.5, width: 0.5, height: 0.5), NormRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
        case .featured:
            let small = max(1, n - 1)
            if portrait {
                let mainH = 0.68
                rects = [NormRect(x: 0, y: 0, width: 1, height: mainH)]
                for i in 0..<small {
                    rects.append(NormRect(x: Double(i) / Double(small), y: mainH, width: 1 / Double(small), height: 1 - mainH))
                }
            } else {
                let mainW = 0.72
                rects = [NormRect(x: 0, y: 0, width: mainW, height: 1)]
                for i in 0..<small {
                    rects.append(NormRect(x: mainW, y: Double(i) / Double(small), width: 1 - mainW, height: 1 / Double(small)))
                }
            }
        }
        rects = Array(rects.prefix(n))
        guard gap > 0, rects.count > 1 else { return rects }
        // Equal visual gaps: half the gap on each side of every inner edge.
        let dx = gap / 2
        let dy = gap / 2 * canvas.aspect
        return rects.map { r in
            let left = r.x > 0.0001 ? dx : 0
            let right = r.maxX < 0.9999 ? dx : 0
            let top = r.y > 0.0001 ? dy : 0
            let bottom = r.maxY < 0.9999 ? dy : 0
            return NormRect(x: r.x + left, y: r.y + top, width: r.width - left - right, height: r.height - top - bottom)
        }
    }
}

extension MulticamEditor {
    /// Grid clips linked to a multicam clip (the other angles of its grid shot).
    public static func gridPartners(of clipID: UUID, in timeline: Timeline) -> [TimelineClip] {
        guard let clip = timeline.clip(id: clipID), let group = clip.linkGroup else { return [] }
        return timeline.tracks.filter { $0.kind == .video }.flatMap(\.clips).filter { $0.linkGroup == group && $0.id != clipID }
    }

    /// The layout a multicam clip currently shows (single when it has no grid partners).
    public static func gridLayout(of clipID: UUID, in timeline: Timeline) -> (count: Int, angles: [UUID]) {
        guard let clip = timeline.clip(id: clipID), let id = clip.assetID else { return (1, []) }
        let partners = gridPartners(of: clipID, in: timeline).compactMap(\.assetID)
        return (1 + partners.count, [id] + partners)
    }

    /// Fits a clip's crop/position/scale so it fills `slot`.
    public static func fill(_ clip: inout TimelineClip, slot: NormRect, canvas: CanvasSettings, sourceSize: Size2, focus: Vec2? = nil) {
        let size = sourceSize.isEmpty ? Size2(1920, 1080) : sourceSize
        let slotAspect = slot.pixelAspect(in: canvas.size)
        let crop = NormRect.crop(aspect: slotAspect, frameSize: size, focus: focus ?? Vec2(0.5, 0.5))
        let placement = LayerGeometry.placement(fillingSlot: slot, cropAspect: slotAspect, canvasSize: canvas.size)
        clip.transform.crop = crop
        clip.transform.fit = .fit
        clip.transform.positionX = AnimatedDouble(placement.positionX)
        clip.transform.positionY = AnimatedDouble(placement.positionY)
        clip.transform.scale = AnimatedDouble(placement.scale)
    }

    static func resetToFullFrame(_ clip: inout TimelineClip) {
        clip.transform = VisualTransform()
        clip.transform.fit = .fill
    }

    /// Turns the multicam shot `clipID` into a grid of `angles` (first = main slot). Angles must have
    /// been recording for the whole shot. `.single` (or one angle) removes the grid.
    public static func applyGrid(_ timeline: inout Timeline, clipID: UUID, angles requested: [UUID], layout: MulticamGridLayout,
                                 group: MulticamGroup, focus: [UUID: Vec2] = [:]) throws {
        guard let clip = timeline.clip(id: clipID), let current = clip.assetID, let from = group.angle(current),
              let mainTrack = timeline.tracks.firstIndex(where: { $0.clips.contains { $0.id == clipID } }) else { throw MulticamError.notMulticam }
        var angles: [UUID] = []
        for id in requested where !angles.contains(id) && group.angle(id)?.hasVideo == true { angles.append(id) }
        if angles.isEmpty { angles = [current] }
        let count = min(layout.capacity, angles.count)
        angles = Array(angles.prefix(count))

        // Every angle must cover the shot.
        let sessionStart = from.sessionTime(atSource: clip.sourceIn)
        let shot = TimeRange(start: sessionStart, duration: clip.sourceDuration)
        for id in angles {
            guard let angle = group.angle(id) else { throw MulticamError.notMulticam }
            guard angle.sessionRange.start <= shot.start + 0.001, angle.sessionRange.end >= shot.end - 0.05 else {
                throw MulticamError.angleNotAvailable(angle.name)
            }
        }

        // Remove the previous grid of this shot.
        let oldPartners = gridPartners(of: clipID, in: timeline).map(\.id)
        if !oldPartners.isEmpty { timeline.delete(clipIDs: oldPartners, ripple: false, includeLinked: false) }

        if layout == .single || count < 2 {
            if angles[0] != current { try switchAngle(&timeline, clipID: clipID, to: angles[0], group: group) }
            timeline.updateClip(id: clipID) { c in
                resetToFullFrame(&c)
                c.linkGroup = nil
            }
            return
        }

        let slots = layout.slots(count: count, canvas: timeline.canvas)
        let link = UUID()
        if angles[0] != current { try switchAngle(&timeline, clipID: clipID, to: angles[0], group: group) }
        let main = group.angle(angles[0])!
        let canvas = timeline.canvas
        timeline.updateClip(id: clipID) { c in
            fill(&c, slot: slots[0], canvas: canvas, sourceSize: main.size, focus: focus[main.assetID])
            c.linkGroup = link
        }
        guard let placed = timeline.clip(id: clipID) else { return }
        for i in 1..<count {
            let angle = group.angle(angles[i])!
            let trackID = gridTrack(&timeline, index: i, above: mainTrack)
            var cell = TimelineClip(name: angle.name, content: .media(assetID: angle.assetID), start: placed.start,
                                    sourceIn: angle.sourceTime(atSession: sessionStart), sourceDuration: placed.sourceDuration,
                                    speed: placed.speed, linkGroup: link, role: angle.role == .gameplay ? .gameplay : .camera)
            fill(&cell, slot: slots[i], canvas: canvas, sourceSize: angle.size, focus: focus[angle.assetID])
            try timeline.insert(cell, onTrack: trackID)
        }
    }

    /// Removes the grid from a shot (back to one full-frame angle).
    public static func removeGrid(_ timeline: inout Timeline, clipID: UUID, group: MulticamGroup) throws {
        try applyGrid(&timeline, clipID: clipID, angles: [], layout: .single, group: group)
    }

    /// The video track holding the grid cell `index` (1-based after the main angle), created above
    /// the multicam track when missing.
    static func gridTrack(_ timeline: inout Timeline, index: Int, above mainTrack: Int) -> UUID {
        let name = "Grid \(index + 1)"
        if let existing = timeline.tracks.first(where: { $0.kind == .video && $0.name == name }) { return existing.id }
        let track = Track(kind: .video, name: name)
        let position = min(timeline.tracks.count, mainTrack + index)
        timeline.tracks.insert(track, at: position)
        return track.id
    }

    /// The multicam shots (main-track clips) inside a timeline range, splitting at its edges.
    public static func shots(_ timeline: inout Timeline, in range: TimeRange, group: MulticamGroup) -> [UUID] {
        func isMain(_ c: TimelineClip) -> Bool { c.assetID.map { group.angle($0) != nil } ?? false }
        guard let track = timeline.tracks.first(where: { t in t.kind == .video && t.clips.contains(where: isMain) }) else { return [] }
        for edge in [range.start, range.end] {
            if let clip = track.clips.first(where: { isMain($0) && $0.start < edge - 0.01 && $0.end > edge + 0.01 }) {
                _ = try? timeline.split(at: edge, clipIDs: [clip.id])
            }
        }
        guard let refreshed = timeline.tracks.first(where: { $0.id == track.id }) else { return [] }
        return refreshed.clips.filter { isMain($0) && $0.start >= range.start - 0.01 && $0.end <= range.end + 0.01 }.map(\.id)
    }
}
