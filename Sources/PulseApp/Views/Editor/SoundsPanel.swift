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
            }
            Spacer(minLength: 4)
            Button { session.addLibrarySound(sound) } label: { Image(systemName: "plus") }
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
