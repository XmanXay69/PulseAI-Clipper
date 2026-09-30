import XCTest
@testable import PulseCore

final class FoundationTests: XCTestCase {
    func testTimeRangeMergeAndComplement() {
        let ranges = [TimeRange(start: 5, end: 7), TimeRange(start: 0, end: 2), TimeRange(start: 1, end: 3)]
        XCTAssertEqual(ranges.merged(), [TimeRange(start: 0, end: 3), TimeRange(start: 5, end: 7)])
        XCTAssertEqual(ranges.totalDuration, 5, accuracy: 1e-9)
        let gaps = ranges.complement(within: TimeRange(start: 0, end: 10))
        XCTAssertEqual(gaps, [TimeRange(start: 3, end: 5), TimeRange(start: 7, end: 10)])
    }

    func testTimeRangeIoU() {
        let a = TimeRange(start: 0, end: 10)
        let b = TimeRange(start: 5, end: 15)
        XCTAssertEqual(a.iou(b), 5.0 / 15.0, accuracy: 1e-9)
        XCTAssertEqual(a.iou(TimeRange(start: 20, end: 30)), 0)
    }

    func testTimecodeFormattingAndParsing() {
        XCTAssertEqual(Timecode.short(2537), "42:17")
        XCTAssertEqual(Timecode.short(3723), "1:02:03")
        XCTAssertEqual(Timecode.string(61.5, fps: 30), "00:01:01:15")
        XCTAssertEqual(Timecode.duration(30), "30s")
        XCTAssertEqual(Timecode.duration(65), "1m 05s")
        XCTAssertEqual(Timecode.parse("00:01:02,500")!, 62.5, accuracy: 1e-9)
        XCTAssertEqual(Timecode.parse("42:17")!, 2537, accuracy: 1e-9)
        XCTAssertNil(Timecode.parse("abc"))
    }

    func testKeyframeInterpolation() {
        var v = AnimatedDouble(1)
        XCTAssertEqual(v.value(at: 3), 1)
        v.setKeyframe(at: 0, value: 0, interpolation: .linear)
        v.setKeyframe(at: 10, value: 10, interpolation: .linear)
        XCTAssertEqual(v.value(at: 5), 5, accuracy: 1e-9)
        XCTAssertEqual(v.value(at: -1), 0)
        XCTAssertEqual(v.value(at: 20), 10)
        v.setKeyframe(at: 0, value: 0, interpolation: .hold)
        XCTAssertEqual(v.value(at: 9.9), 0)
        v.setKeyframe(at: 0, value: 0, interpolation: .easeInOut)
        XCTAssertEqual(v.value(at: 5), 5, accuracy: 1e-9)
        XCTAssertLessThan(v.value(at: 2), 2)
    }

    func testRetainKeyframesForSplit() {
        var v = AnimatedDouble(1)
        v.setKeyframe(at: 1, value: 1)
        v.setKeyframe(at: 6, value: 2)
        var right = v
        right.retainKeyframes(in: TimeRange(start: 5, end: 10), rebasingTo: 5)
        XCTAssertEqual(right.keyframes.count, 1)
        XCTAssertEqual(right.keyframes[0].time, 1, accuracy: 1e-9)
    }

    func testHistoryUndoRedoAndCoalescing() {
        var h = History<Int>(limit: 3, coalesceWindow: 1)
        let t0 = Date()
        h.record(0, label: "A", now: t0)
        h.record(1, label: "drag", coalesceKey: "x", now: t0.addingTimeInterval(2))
        h.record(2, label: "drag", coalesceKey: "x", now: t0.addingTimeInterval(2.5))
        XCTAssertEqual(h.undoStack.count, 2, "coalesced drag should be one step")
        XCTAssertEqual(h.undo(current: 3), 1)
        XCTAssertEqual(h.redo(current: 1), 3)
        h.record(3, label: "B", now: t0.addingTimeInterval(10))
        h.record(4, label: "C", now: t0.addingTimeInterval(11))
        XCTAssertEqual(h.undoStack.count, 3, "limit enforced")
        XCTAssertFalse(h.canRedo)
    }

    func testNormRectCropAspect() {
        let crop = NormRect.crop(aspect: 9.0 / 16.0, frameSize: Size2(1920, 1080), focus: Vec2(0.9, 0.5))
        XCTAssertEqual(crop.pixelAspect(in: Size2(1920, 1080)), 9.0 / 16.0, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(crop.maxX, 1 + 1e-9)
        XCTAssertEqual(crop.height, 1, accuracy: 1e-9)
    }

    func testColorHex() {
        let c = RGBAColor(hex: "#FF3D6E")!
        XCTAssertEqual(c.hexString, "#FF3D6E")
        XCTAssertNil(RGBAColor(hex: "nope"))
    }

    func testFloatSeriesRoundTrip() throws {
        let series = FloatSeries([0, -12.5, 3.25, -100])
        let data = try JSONEncoder().encode(series)
        let decoded = try JSONDecoder().decode(FloatSeries.self, from: data)
        XCTAssertEqual(decoded.values, series.values)
    }

    func testSeriesMathRollingMedianAndPeaks() {
        let values: [Float] = [1, 1, 1, 9, 1, 1, 1, 1, 7, 1]
        let med = SeriesMath.rollingMedian(values, radius: 1)
        XCTAssertEqual(med[3], 1)
        let peaks = SeriesMath.peaks(values, threshold: 5, minDistance: 2)
        XCTAssertEqual(peaks, [3, 8])
    }

    func testLayerGeometryFitAndPlacement() {
        var t = VisualTransform()
        t.crop = NormRect.crop(aspect: 1080.0 / 1114.0, frameSize: Size2(1920, 1080))
        let slot = NormRect(x: 0, y: 0, width: 1, height: 0.58)
        let canvas = Size2(1080, 1920)
        let p = LayerGeometry.placement(fillingSlot: slot, cropAspect: slot.pixelAspect(in: canvas), canvasSize: canvas)
        t.positionX = AnimatedDouble(p.positionX)
        t.positionY = AnimatedDouble(p.positionY)
        t.scale = AnimatedDouble(p.scale)
        let g = LayerGeometry.resolve(t, at: 0, sourceSize: Size2(1920, 1080), canvasSize: canvas)
        XCTAssertEqual(g.size.width, 1080, accuracy: 1)
        XCTAssertEqual(g.size.height, 1920 * 0.58, accuracy: 1)
        XCTAssertEqual(g.frame.y, 0, accuracy: 1)
    }

    func testEffectiveCropZoomStaysInside() {
        var t = VisualTransform()
        t.crop = NormRect(x: 0.6, y: 0, width: 0.4, height: 1)
        t.zoom = AnimatedDouble(1.25)
        t.panX = AnimatedDouble(0.3)
        let c = t.effectiveCrop(at: 0)
        XCTAssertLessThanOrEqual(c.maxX, 1 + 1e-9)
        XCTAssertEqual(c.width, 0.32, accuracy: 1e-6)
    }
}
