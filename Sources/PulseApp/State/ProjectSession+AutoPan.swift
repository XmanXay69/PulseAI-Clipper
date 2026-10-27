import Foundation
import PulseCore

extension ProjectSession {
    /// Timeline → Pan Voice Toward the Facecam (#271): the audio linked to each facecam leans a little toward
    /// the side of the canvas the facecam sits on.
    func panTowardFacecam() {
        guard let timeline = activeTimeline else { return }
        var changed = 0
        editTimeline("Pan Toward Facecam") { t in changed = AutoPan.apply(to: &t) }
        if changed == 0 {
            app.toast(timeline.allClips.contains(where: { $0.role == .webcam || $0.role == .camera })
                      ? "The facecam sits in the middle — nothing to lean toward" : "No facecam clip on this timeline")
        } else {
            app.toast("\(changed) voice clip\(changed == 1 ? "" : "s") now lean\(changed == 1 ? "s" : "") toward the facecam (subtle, ±20 %)")
        }
    }
}
