import Foundation
import PulseCore
import PulseEngine

/// The built-in music & sound-effects library: importing sounds into the project and placing them.
extension ProjectSession {
    static func libraryLength(_ sound: LibrarySound, _ duration: Seconds?) -> Seconds? {
        guard sound.kind == .music else { return nil }
        return ((duration ?? SoundLibrary.defaultMusicLength) * 10).rounded() / 10
    }

    /// The project's copy of a library sound (music: at this length), if it was imported before.
    func libraryAsset(_ sound: LibrarySound, duration: Seconds?) -> MediaAsset? {
        let tags = sound.assetTags(duration: Self.libraryLength(sound, duration))
        return document.media.first { asset in
            asset.availability != .missing && tags.allSatisfy { tag in !tag.hasPrefix("library") || asset.tags.contains(tag) }
        }
    }

    /// Renders (first time only) and probes a library sound. `isNew` = not in the project yet.
    func prepareLibrarySound(_ sound: LibrarySound, duration: Seconds? = nil) async throws -> (asset: MediaAsset, isNew: Bool) {
        if let existing = libraryAsset(sound, duration: duration) { return (existing, false) }
        let length = Self.libraryLength(sound, duration)
        let url = try await SoundLibraryStore.shared.file(for: sound, duration: length)
        let asset = try await SoundLibraryStore.asset(for: sound, url: url, duration: length, cacheRoot: app.cacheFolder)
        return (asset, true)
    }

    /// Adds a library sound to the active timeline: effects at the playhead, music as a ducked bed composed
    /// to run exactly from the playhead (or the start) to the end of the edit.
    func addLibrarySound(_ sound: LibrarySound) {
        guard let timeline = activeTimeline else {
            app.toast("Open a timeline to add sounds")
            return
        }
        let isMusic = sound.kind == .music
        let start = isMusic && playhead >= timeline.duration - 1 ? 0 : playhead
        let length: Seconds? = isMusic ? max(3, timeline.duration > 1 ? timeline.duration - start : SoundLibrary.defaultMusicLength) : nil
        let timelineID = timeline.id
        app.jobs.start("Adding \(sound.name)", kind: .importMedia) { [weak self] job in
            guard let self else { return }
            job.detail = isMusic ? "Composing \(Timecode.duration(length ?? 0)) of \(sound.category) music" : "Rendering"
            let (asset, isNew) = try await self.prepareLibrarySound(sound, duration: length)
            var clipID: UUID?
            self.edit("Add \(sound.name)") { doc in
                if isNew { doc.media.append(asset) }
                doc.updateTimeline(id: timelineID) { t in
                    let available = asset.metadata.duration > 0 ? asset.metadata.duration : (length ?? 1)
                    var clip = TimelineClip(name: asset.name, content: .media(assetID: asset.id), start: start,
                                            sourceDuration: min(available, length ?? available), role: isMusic ? .music : .soundEffect)
                    if isMusic {
                        clip.audio.volume = AnimatedDouble(0.35)
                        clip.audio.duckUnderDialogue = true
                        clip.audio.fadeIn = 0.5
                        clip.audio.fadeOut = 1.2
                    } else {
                        clip.audio.volume = AnimatedDouble(0.7)
                    }
                    let trackID = t.freeTrack(kind: .audio, for: clip.timelineRange)
                    if (try? t.insert(clip, onTrack: trackID, mode: .overwrite)) != nil { clipID = clip.id }
                }
            }
            if let clipID { self.selectedClipIDs = [clipID] }
            self.app.toast(isMusic ? "\(sound.name) added — composed to fit, ducked under speech" : "\(sound.name) added at the playhead")
        }
    }

    /// Clip tags of the candidate a timeline was built from (for picking music).
    func candidateTags(for timelineID: UUID) -> [ClipTag] {
        document.candidates.first { $0.timelineID == timelineID }?.tags ?? []
    }

    /// After a short is built: fill in a music bed and a payoff hit from the library when the AI settings
    /// ask for them but the project has none of its own.
    func addLibraryAudio(toShort timelineID: UUID, music: Bool, effects: Bool) {
        guard music || effects, let timeline = document.timeline(id: timelineID) else { return }
        let tags = candidateTags(for: timelineID)
        let payoff = timeline.markers.first { $0.name == "Payoff" }?.time
        let seed = abs(timelineID.hashValue)
        app.jobs.start("AI music & sound effects", kind: .autoEdit) { [weak self] job in
            guard let self else { return }
            var newAssets: [MediaAsset] = []
            var bed: MediaAsset?
            var hit: MediaAsset?
            if music {
                let sound = SoundLibrary.recommendedMusic(for: tags, seed: seed)
                job.detail = "Composing \(sound.name)"
                let prepared = try await self.prepareLibrarySound(sound, duration: max(3, timeline.duration))
                bed = prepared.asset
                if prepared.isNew { newAssets.append(prepared.asset) }
            }
            if effects, payoff != nil, let sound = SoundLibrary.sound(id: "sfx.impact") {
                job.detail = "Rendering \(sound.name)"
                let prepared = try await self.prepareLibrarySound(sound)
                hit = prepared.asset
                if prepared.isNew { newAssets.append(prepared.asset) }
            }
            self.edit("AI Music & Sound Effects") { doc in
                doc.media.append(contentsOf: newAssets)
                doc.updateTimeline(id: timelineID) { t in
                    if let bed { ShortBuilder.addMusicBed(bed, to: &t) }
                    if let hit, let payoff { ShortBuilder.addPayoffHit(hit, at: payoff, to: &t) }
                }
            }
            let names = [bed?.name, hit?.name].compactMap { $0 }
            self.app.logActivity(.autoEdit, title: "Added library audio", detail: names.joined(separator: " · "))
        }
    }

    /// Imports the library sounds an entertainment pass needs when the project has none of its own,
    /// then runs it.
    func makeMoreEntertainingWithLibrary(options: EntertainmentOptions) {
        guard let timeline = activeTimeline else { return }
        let needsEffects = options.soundEffects && !document.media.contains { $0.role == .soundEffect }
        let needsMusic = options.music && !document.media.contains { $0.role == .music }
        guard needsEffects || needsMusic else {
            applyEntertainment(options: options)
            return
        }
        let tags = candidateTags(for: timeline.id)
        app.jobs.start("Preparing sounds", kind: .autoEdit) { [weak self] job in
            guard let self else { return }
            var newAssets: [MediaAsset] = []
            if needsEffects, let whoosh = SoundLibrary.sound(id: "sfx.whoosh") {
                let prepared = try await self.prepareLibrarySound(whoosh)
                if prepared.isNew { newAssets.append(prepared.asset) }
            }
            if needsMusic {
                let sound = SoundLibrary.recommendedMusic(for: tags)
                job.detail = "Composing \(sound.name)"
                let prepared = try await self.prepareLibrarySound(sound, duration: max(3, timeline.duration))
                if prepared.isNew { newAssets.append(prepared.asset) }
            }
            if !newAssets.isEmpty { self.edit("Add Library Sounds") { $0.media.append(contentsOf: newAssets) } }
            self.applyEntertainment(options: options)
        }
    }
}
