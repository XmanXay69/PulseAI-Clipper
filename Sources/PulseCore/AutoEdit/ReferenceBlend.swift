import Foundation

extension ReferenceStyle {
    /// Halfway (or `weight` of the way) between two references (#367): every measurement averaged, the
    /// caption look too when both have one.
    public func blended(with other: ReferenceStyle, weight: Double = 0.5, name: String? = nil) -> ReferenceStyle {
        let w = weight.clamped(0, 1)
        func mix(_ a: Double, _ b: Double) -> Double { a * (1 - w) + b * w }
        func mixOpt(_ a: Double?, _ b: Double?) -> Double? {
            switch (a, b) {
            case let (x?, y?): return mix(x, y)
            case let (x?, nil): return x
            case let (nil, y?): return y
            default: return nil
            }
        }
        var captionLook: CaptionLook?
        switch (captions, other.captions) {
        case let (a?, b?):
            captionLook = CaptionLook(coverage: mix(a.coverage, b.coverage), positionY: mix(a.positionY, b.positionY), lineHeight: mix(a.lineHeight, b.lineHeight),
                                      wordsOnScreen: mix(a.wordsOnScreen, b.wordsOnScreen), uppercase: w < 0.5 ? a.uppercase : b.uppercase)
        case let (a?, nil): captionLook = w < 0.75 ? a : nil
        case let (nil, b?): captionLook = w > 0.25 ? b : nil
        default: captionLook = nil
        }
        return ReferenceStyle(name: name ?? "\(self.name) + \(other.name)", duration: mix(duration, other.duration), aspect: mix(aspect, other.aspect),
                              cutsPerMinute: mix(cutsPerMinute, other.cutsPerMinute), averageShotLength: mix(averageShotLength, other.averageShotLength),
                              zoomsPerMinute: mix(zoomsPerMinute, other.zoomsPerMinute), zoomScale: mix(zoomScale, other.zoomScale), captions: captionLook,
                              popupsPerMinute: mix(popupsPerMinute, other.popupsPerMinute), wordsPerMinute: mixOpt(wordsPerMinute, other.wordsPerMinute),
                              pauseRatio: mixOpt(pauseRatio, other.pauseRatio), musicBed: mix(musicBed, other.musicBed),
                              effectsPerMinute: mix(effectsPerMinute, other.effectsPerMinute), fadesPerMinute: mix(fadesPerMinute, other.fadesPerMinute),
                              opensFast: w < 0.5 ? opensFast : other.opensFast)
    }
}
