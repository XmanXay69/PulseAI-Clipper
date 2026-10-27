import Foundation
import PulseCore
import PulseEngine

extension ProjectSession {
    /// Runs a signal plugin over a recording (#495): the plugin gets the file path, duration and transcript on
    /// stdin and prints events, which then score like banners (and re-score the clips when analyzed).
    func runSignalPlugin(_ plugin: PluginRegistry.Loaded, assetID: UUID) {
        guard let asset = document.asset(id: assetID) else { return }
        let words = (analyses[assetID]?.transcript?.words ?? []).map { PluginRegistry.SignalInput.Word(text: $0.text, start: $0.start, end: $0.end) }
        let input = PluginRegistry.SignalInput(mediaPath: url(for: asset).path, assetName: asset.name, duration: asset.metadata.duration, transcript: words)
        let name = plugin.manifest.name
        app.jobs.start("Signal plugin · \(name)", kind: .analysis) { [weak self] job in
            guard let self else { return }
            job.detail = words.isEmpty ? "No transcript yet — the plugin gets the file and its length" : "\(words.count) transcript words handed over"
            let events = try await PluginRegistry.shared.runSignal(plugin, input: input)
            guard !events.isEmpty else { self.app.toast("\(name) found nothing in \(asset.name)"); return }
            self.attachGameEvents(events, to: assetID, source: "plugin \(name)")
        }
    }
}
