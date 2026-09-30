import AVFoundation
import CoreMedia
import Foundation
import PulseCore

/// What a render layer draws.
public enum RenderLayerContent: @unchecked Sendable {
    /// Frames from a composition video track.
    case video(trackID: CMPersistentTrackID, sourceSize: Size2, orientation: CGImagePropertyOrientation)
    /// A still image file.
    case image(url: URL, size: Size2)
    case text(TextElement)
    case solid(RGBAColor)
}

/// One visual layer active during an instruction, bottom → top.
public struct RenderLayer: @unchecked Sendable {
    public var content: RenderLayerContent
    public var clip: TimelineClip
    public var trackOpacity: Double
}

/// Caption data shared by every instruction of a composition.
public struct CaptionRenderData: @unchecked Sendable {
    public var pages: [CaptionPage]
    public var style: CaptionStyle
}

/// Settings shared by the whole composition.
public final class RenderScene: @unchecked Sendable {
    public let canvas: CanvasSettings
    public let renderSize: CGSize
    public let captions: CaptionRenderData?
    public let showSafeArea: SafeAreaPlatform?

    public init(canvas: CanvasSettings, renderSize: CGSize, captions: CaptionRenderData?, showSafeArea: SafeAreaPlatform? = nil) {
        self.canvas = canvas
        self.renderSize = renderSize
        self.captions = captions
        self.showSafeArea = showSafeArea
    }

    /// Output pixels per canvas unit.
    public var renderScale: Double { Double(renderSize.width) / Double(max(canvas.width, 1)) }
}

/// Custom instruction consumed by `PulseVideoCompositor`.
public final class PulseCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    public let timeRange: CMTimeRange
    public let enablePostProcessing = false
    public let containsTweening = true
    public let requiredSourceTrackIDs: [NSValue]?
    public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    public let layers: [RenderLayer]
    public let scene: RenderScene

    public init(timeRange: CMTimeRange, layers: [RenderLayer], scene: RenderScene) {
        self.timeRange = timeRange
        self.layers = layers
        self.scene = scene
        let ids: [NSValue] = layers.compactMap {
            if case .video(let trackID, _, _) = $0.content { return NSNumber(value: trackID) }
            return nil
        }
        self.requiredSourceTrackIDs = ids.isEmpty ? nil : ids
        super.init()
    }
}

extension CGImagePropertyOrientation {
    /// Maps a track's preferredTransform to an EXIF orientation for Core Image.
    init(transform t: CGAffineTransform) {
        let angle = atan2(Double(t.b), Double(t.a))
        let degrees = Int((angle * 180 / .pi).rounded())
        switch (degrees + 360) % 360 {
        case 90: self = .right
        case 180: self = .down
        case 270: self = .left
        default: self = .up
        }
    }

    var swapsDimensions: Bool { self == .left || self == .right || self == .leftMirrored || self == .rightMirrored }
}
