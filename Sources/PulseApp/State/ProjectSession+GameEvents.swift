import AppKit
import Foundation
import PulseCore

extension ProjectSession {
    /// Import Game Events… (#488): a Riot Live Client Data log, or a CSV / JSON list of timestamps, attached
    /// to a recording as exact banners. The log runs on the game's clock, so it asks where the game's 0:00
    /// sits in the recording.
    func importGameEvents(_ url: URL, for assetID: UUID?) {
        guard let data = try? Data(contentsOf: url), let parsed = GameEventLog.parse(data: data) else {
            app.presentMessage(title: "Couldn't read the game events",
                               message: "Expected a Riot Live Client Data event log, a CSV with time,kind,text lines, or a JSON list of {time, kind, text}.")
            return
        }
        guard let target = assetID ?? document.primaryAsset?.id, let asset = document.asset(id: target) else {
            app.toast("Import the recording first, then its game events")
            return
        }
        let alert = NSAlert()
        alert.messageText = "\(parsed.events.count) events from \(parsed.source.rawValue)"
        alert.informativeText = "Where does the game's 0:00 sit in “\(asset.name)”? Enter the recording time (mm:ss or seconds) at which the game clock started. 0 if the recording began with the game."
        let field = NSTextField(string: "0")
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let offset = GameEventLog.seconds(from: field.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        attachGameEvents(GameEventLog.shift(parsed.events, by: offset), to: target, source: parsed.source.rawValue)
    }

    func attachGameEvents(_ events: [HUDEvent], to assetID: UUID, source: String) {
        guard !events.isEmpty else { app.toast("No events land inside the recording"); return }
        edit("Import Game Events") { doc in
            doc.updateAsset(id: assetID) { $0.gameEvents = GameEventLog.merge($0.gameEvents, adding: events) }
        }
        var analysis = analyses[assetID] ?? MediaAnalysis(assetID: assetID, duration: document.asset(id: assetID)?.metadata.duration ?? 0)
        analysis.hudEvents = GameEventLog.merge(analysis.hudEvents ?? [], adding: events)
        setAnalysis(analysis)
        signalCache[assetID] = nil
        app.logActivity(.analysis, title: "\(events.count) game events added", detail: source)
        if analysis.audio != nil || analysis.transcript != nil {
            app.toast("\(events.count) game events added — re-scoring clips with them")
            generateCandidates(assetID: assetID)
        } else {
            app.toast("\(events.count) game events added — they'll be used when the recording is analyzed")
        }
    }
}
