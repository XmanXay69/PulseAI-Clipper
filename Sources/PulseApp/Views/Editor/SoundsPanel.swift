import AVFoundation
import PulseCore
import PulseEngine
import SwiftUI

/// Built-in music & sound effects: browse, preview and add to the edit.
struct SoundsPanel: View {
    @ObservedObject var session: ProjectSession
    @StateObject private var preview = SoundPreviewPlayer()
    @State private var kind: LibrarySound.Kind = .music
    @State private var category: String?
    @State private var query = ""
    @ObservedObject private var connectivity = Connectivity.shared

    var results: [LibrarySound] { SoundLibrary.search(query, kind: kind, category: category) }
    var categories: [String] { kind == .music ? SoundLibrary.musicCategories : SoundLibrary.effectCategories }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $kind) {
                    Text("Music").tag(LibrarySound.Kind.music)
                    Text("Sound Effects").tag(LibrarySound.Kind.soundEffect)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: kind) { _, _ in category = nil }
                TextField(kind == .music ? "Search moods: hype, chill, funny…" : "Search: whoosh, boom, ding…", text: $query)
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                if !connectivity.isOnline {
                    TagChip(text: "Offline — PULSE's own library only", color: Theme.warning, symbol: "wifi.slash")
                        .help("Creative Commons search and downloads wait for a connection; everything here is built in (#300)")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        chip("All", selected: category == nil) { category = nil }
                        ForEach(categories, id: \.self) { c in chip(c, selected: category == c) { category = category == c ? nil : c } }
                    }
                }
            }
            .padding(8)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(results) { sound in row(sound) }
                    if results.isEmpty {
                        Text("Nothing matches “\(query)”.").font(.pulseCaption).foregroundStyle(Theme.textTertiary).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 8)
                Text(kind == .music
                     ? "Composed on this Mac by PULSE — royalty-free, safe for monetized videos. Music is written to fit: added tracks end exactly where your edit ends, ducked under speech."
                     : "Synthesized on this Mac by PULSE — royalty-free. Added at the playhead.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    .padding(10)
            }
        }
        .onDisappear { preview.stop() }
    }

    func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.pulseMicro)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .background(Capsule().fill(selected ? Theme.accentSoft : Theme.control))
        }
        .buttonStyle(.plain)
    }

    func row(_ sound: LibrarySound) -> some View {
        let playing = preview.playingID == sound.id
        let loading = preview.loadingID == sound.id
        return HStack(spacing: 8) {
            Button { preview.toggle(sound) } label: {
                ZStack {
                    Circle().fill(playing ? Theme.accent : Theme.control).frame(width: 26, height: 26)
                    if loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 10)).foregroundStyle(playing ? .white : Theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(playing ? "Stop preview" : "Preview")
            VStack(alignment: .leading, spacing: 1) {
                Text(sound.name).font(.pulseCaption.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text([sound.category, sound.bpm.map { "\($0) BPM" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.pulseMicro).foregroundStyle(sound.kind == .music ? Theme.musicClip : Theme.sfxClip).lineLimit(1)
                Text(sound.summary).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(2)
                if let url = preview.urls[sound.id] {
                    SoundDropStrip(url: url, color: sound.kind == .music ? Theme.musicClip : Theme.sfxClip)
                        .frame(height: 14)
                }
            }
            Spacer(minLength: 4)
            Button { session.addLibrarySound(sound) } label: { Image(systemName: "plus") }
                .contextMenu {
                    if sound.kind == .soundEffect {
                        ForEach(SoundLibrary.variations, id: \.self) { semitones in
                            Button(SoundLibrary.variantName(sound, semitones: semitones) + " semitones") { session.addLibrarySound(sound, semitones: semitones) }
                        }
                    }
                }
                .buttonStyle(.pulse(.secondary, compact: true))
                .help(sound.kind == .music ? "Add as a music bed that fits the edit" : "Add at the playhead")
                .disabled(session.activeTimeline == nil)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(playing ? Theme.panelRaised : .clear))
        .contentShape(Rectangle())
    }
}

/// Plays library previews (music: a 20-second rendering).
@MainActor
final class SoundPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingID: String?
    @Published var loadingID: String?
    /// Rendered preview files by sound id, for the waveform under a sound once it has played (#293).
    @Published var urls: [String: URL] = [:]
    private var player: AVAudioPlayer?

    func toggle(_ sound: LibrarySound) {
        if playingID == sound.id || loadingID == sound.id {
            stop()
            return
        }
        stop()
        loadingID = sound.id
        Task {
            do {
                let url = try await SoundLibraryStore.shared.file(for: sound, duration: sound.kind == .music ? 20 : nil)
                urls[sound.id] = url
                guard loadingID == sound.id else { return }
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                player.play()
                self.player = player
                playingID = sound.id
            } catch {
                playingID = nil
            }
            if loadingID == sound.id { loadingID = nil }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
        loadingID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.playingID = nil }
        }
    }
}


/// A sound's preview waveform with its drop marked (#293): the loudest sustained moment, "drop at 0:42".
struct SoundDropStrip: View {
    let url: URL
    var color: Color = Theme.musicClip
    @State private var duration: Seconds = 0
    @State private var drop: Seconds?

    var body: some View {
        HStack(spacing: 6) {
            WaveformStrip(url: url, sourceRange: TimeRange(start: 0, end: max(duration, 0.1)), color: color)
                .overlay {
                    if let drop, duration > 0 {
                        GeometryReader { geo in
                            Rectangle().fill(Theme.accent).frame(width: 1.5)
                                .offset(x: max(0, min(geo.size.width - 1.5, CGFloat(drop / duration) * geo.size.width)))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            if let drop { Text("drop \(Timecode.short(drop))").font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize() }
        }
        .task(id: url) {
            let peaks = await WaveformService.shared.peaks(for: url)
            let perSecond = Double(WaveformService.peaksPerSecond)
            duration = Double(peaks.count) / perSecond
            // The drop: the second whose energy jumps most over the three seconds before it, after the first bar.
            let window = Int(perSecond)
            guard peaks.count > window * 5 else { drop = nil; return }
            var best: (Seconds, Float) = (0, 0)
            var i = window * 3
            while i + window <= peaks.count {
                let now = peaks[i..<(i + window)].reduce(0, +) / Float(window)
                let before = peaks[(i - window * 3)..<i].reduce(0, +) / Float(window * 3)
                let jump = now - before
                if jump > best.1 { best = (Double(i) / perSecond, jump) }
                i += window / 2
            }
            drop = best.1 > 0.08 ? best.0 : nil
        }
    }
}
