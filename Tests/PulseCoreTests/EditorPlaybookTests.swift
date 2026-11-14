import XCTest
@testable import PulseCore

final class EditorPlaybookTests: XCTestCase {
    func testEveryPlaybookIsDistinctAndFindsItselfByItsStyle() {
        let all = EditorPlaybook.all
        XCTAssertEqual(all.count, 6)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(all.map(\.style.id)).count, all.count)
        for playbook in all {
            XCTAssertEqual(EditorPlaybook.playbook(id: playbook.id), playbook)
            XCTAssertEqual(EditorPlaybook.playbook(for: playbook.style), playbook)
            XCTAssertGreaterThanOrEqual(playbook.principles.count, 4)
            XCTAssertFalse(playbook.recipe.isEmpty)
            XCTAssertLessThanOrEqual(playbook.rules.openingStaticStretch, playbook.rules.maxStaticStretch, playbook.id)
            XCTAssertEqual(playbook.style.name, playbook.name)
        }
        // The same identity on every launch, so a style used last week is still that style.
        XCTAssertEqual(EditorPlaybook.styleID(1), EditorPlaybook.retention.style.id)
        XCTAssertEqual(EditorPlaybook.styleID(1).uuidString, "50554C53-4500-4000-8000-000000000001")
        XCTAssertNil(EditorPlaybook.playbook(for: ReferenceStyle(name: "Mine", duration: 600, aspect: 1.78, cutsPerMinute: 5, averageShotLength: 12,
                                                                 zoomsPerMinute: 1, zoomScale: 1.1, captions: nil, popupsPerMinute: 0, wordsPerMinute: nil,
                                                                 pauseRatio: nil, musicBed: 0, effectsPerMinute: 0, fadesPerMinute: 0, opensFast: false)))
    }

    func testPlaybooksBecomeTheEditsTheyDescribe() {
        func options(_ playbook: EditorPlaybook) -> LongFormOptions { playbook.style.longFormOptions(.recommended(for: playbook.style)) }

        let fast = options(.retention)
        XCTAssertEqual(fast.restraint, .energetic)
        XCTAssertEqual(fast.style?.silence, .aggressive)
        XCTAssertTrue(fast.zooms && fast.captions && fast.music && fast.soundEffects && fast.memes && fast.coldOpen)
        XCTAssertEqual(fast.style?.rhythmZooms, true)
        XCTAssertEqual(fast.zoomSpacing, 12, accuracy: 0.01)
        XCTAssertEqual(fast.style?.captionLook?.uppercase, true)

        let calm = options(.commentary)
        XCTAssertEqual(calm.restraint, .subtle)
        XCTAssertTrue(calm.captions)
        XCTAssertFalse(calm.memes || calm.soundEffects || calm.music)
        XCTAssertEqual(calm.style?.rhythmZooms, false)
        XCTAssertGreaterThan(calm.zoomSpacing, fast.zoomSpacing * 4)

        let story = options(.story)
        XCTAssertEqual(story.restraint, .balanced)
        XCTAssertEqual(story.style?.fades, true)
        XCTAssertEqual(story.style?.silence, .balanced)

        let smooth = options(.smooth)
        XCTAssertEqual(smooth.style?.fades, true)
        XCTAssertFalse(smooth.memes)
        XCTAssertLessThan(smooth.style?.zoomScale ?? 2, fast.style?.zoomScale ?? 0)

        let beat = options(.onTheBeat)
        XCTAssertFalse(beat.captions, "a montage has no talking to caption")
        XCTAssertEqual(beat.restraint, .energetic)

        // The short playbook asks for shorts, a word or two at a time.
        let answers = ReferenceAnswers.recommended(for: EditorPlaybook.punchyShort.style)
        XCTAssertEqual(answers.length, .shorts)
        let short = EditorPlaybook.punchyShort.style.shortOptions(answers, base: ShortBuildOptions())
        XCTAssertTrue(short.captionsEnabled && short.punchIns)
        XCTAssertEqual(short.captionStyle.maxWordsPerPage, 2)
        XCTAssertEqual(short.silence, .aggressive)
    }

    func testTheSuggestedPlaybookFollowsTheRecording() {
        XCTAssertEqual(EditorPlaybook.suggested(for: .gameplayWithFacecam), .retention)
        XCTAssertEqual(EditorPlaybook.suggested(for: .gameplay), .retention)
        XCTAssertEqual(EditorPlaybook.suggested(for: .podcast), .commentary)
        XCTAssertEqual(EditorPlaybook.suggested(for: .talkingHead), .commentary)
        XCTAssertEqual(EditorPlaybook.suggested(for: .unknown), .story)
        XCTAssertEqual(EditorPlaybook.suggested(for: .gameplay, format: .short), .punchyShort)
    }

    func testStaticStretchesEndAtCutsZoomsAndPopUps() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        XCTAssertEqual(PlaybookCoach.staticStretches(in: timeline).map(\.duration), [30])

        // A punch-in at 15 s splits the hold in two.
        PunchInGenerator.apply(moments: [.reaction(15)], to: &timeline, trackID: timeline.tracks[0].id)
        let split = PlaybookCoach.staticStretches(in: timeline)
        XCTAssertGreaterThanOrEqual(split.count, 2)
        XCTAssertLessThan(split.map(\.duration).max() ?? 99, 16)
        XCTAssertFalse(split.contains { $0.contains(14.9) }, "the move into the zoom isn't static")

        // A pop-up on the text track is a change when it arrives and when it leaves.
        var popped = Fixtures.simpleTimeline(clipDuration: 30)
        popped.tracks[2].clips = [TimelineClip(name: "Meme", content: .text(TextElement(text: "BRUH")), start: 10, sourceIn: 0, sourceDuration: 2)]
        let around = PlaybookCoach.staticStretches(in: popped)
        XCTAssertEqual(around.count, 3)
        XCTAssertEqual(around[0].end, 10, accuracy: 0.05)
        XCTAssertEqual(around[2].start, 12, accuracy: 0.05)

        // A slow push across the whole shot keeps the frame moving: nothing is static.
        var moving = Fixtures.simpleTimeline(clipDuration: 30)
        XCTAssertEqual(EditPolish.breathingZooms(&moving, from: 0, minimumLength: 20), 1)
        XCTAssertTrue(PlaybookCoach.staticStretches(in: moving).isEmpty)

        // A second clip is a cut.
        var cut = Fixtures.simpleTimeline(clipDuration: 30)
        _ = try? cut.split(at: 12)
        XCTAssertEqual(PlaybookCoach.staticStretches(in: cut).count, 2)
    }

    func testAHeldShotIsCalledOutOnceAndGameplayGetsMoreRoom() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        PunchInGenerator.apply(moments: [.reaction(15)], to: &timeline, trackID: timeline.tracks[0].id)
        let rules = PacingRules.standard(for: .short)

        let advice = PlaybookCoach.suggestions(for: timeline, format: .short, rules: rules)
        let held = try XCTUnwrap(advice.first { $0.id == "static-stretch" })
        XCTAssertEqual(held.fix, .addZooms)
        XCTAssertEqual(held.severity, .recommended, "the opening is held to the tighter figure")
        XCTAssertTrue(held.title.contains("15 s") || held.title.contains("14 s"), held.title)

        // The coach already said "add zooms": not twice.
        XCTAssertFalse(PlaybookCoach.suggestions(for: timeline, format: .short, rules: rules, existing: ["zooms"]).contains { $0.id == "static-stretch" })

        // Moving footage gets twice the room, and a slower style more again.
        var relaxed = rules
        relaxed.openingStaticStretch = 8
        relaxed.maxStaticStretch = 8
        XCTAssertTrue(PlaybookCoach.suggestions(for: timeline, format: .short, rules: relaxed, profile: .talkingHead).contains { $0.id == "static-stretch" })
        XCTAssertFalse(PlaybookCoach.suggestions(for: timeline, format: .short, rules: relaxed, profile: .gameplayWithFacecam).contains { $0.id == "static-stretch" })
        XCTAssertFalse(PlaybookCoach.suggestions(for: timeline, format: .longForm, rules: EditorPlaybook.commentary.rules).contains { $0.id == "static-stretch" })
    }

    func testLongVideosWantANewSectionEveryFewMinutes() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 900)
        timeline.canvas = .landscape1080
        let rules = PacingRules.standard(for: .longForm)
        let advice = PlaybookCoach.suggestions(for: timeline, format: .longForm, rules: rules)
        let rehook = try XCTUnwrap(advice.first { $0.id == "rehook" })
        XCTAssertTrue(rehook.title.contains("15 min"), rehook.title)
        XCTAssertEqual(rehook.fix, EditSuggestion.Fix.none)

        // Chapter markers every two and a half minutes settle it.
        timeline.markers = stride(from: 150.0, to: 900, by: 150).map { Marker(time: $0, name: "Chapter") }
        XCTAssertEqual(PlaybookCoach.resets(in: timeline).count, 5)
        XCTAssertFalse(PlaybookCoach.suggestions(for: timeline, format: .longForm, rules: rules).contains { $0.id == "rehook" })

        // A short has no sections to mark.
        let short = Fixtures.simpleTimeline(clipDuration: 40)
        XCTAssertFalse(PlaybookCoach.suggestions(for: short, format: .short, rules: .standard(for: .short)).contains { $0.id == "rehook" })
    }

    func testTooManyEffectsAndLongCaptionPagesAreTips() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        timeline.tracks[4].clips = (0..<9).map { i in
            TimelineClip(name: "Boom", content: .media(assetID: UUID()), start: Double(i) * 3 + 1, sourceIn: 0, sourceDuration: 0.5, role: .soundEffect)
        }
        let rules = PacingRules.standard(for: .short)
        let busy = try XCTUnwrap(PlaybookCoach.suggestions(for: timeline, format: .short, rules: rules).first { $0.id == "over-sfx" })
        XCTAssertEqual(busy.severity, .tip)
        XCTAssertTrue(busy.detail.contains("9 effects"))
        timeline.tracks[4].clips = Array(timeline.tracks[4].clips.prefix(3))
        XCTAssertFalse(PlaybookCoach.suggestions(for: timeline, format: .short, rules: rules).contains { $0.id == "over-sfx" })

        var style = CaptionStyle.tiktok
        style.maxWordsPerPage = 7
        let transcript = Transcript(language: "en", words: (0..<40).map { TranscriptWord(text: "word", start: 100 + Double($0) * 0.5, end: 100.4 + Double($0) * 0.5) }, source: .demo)
        timeline.captions = CaptionTrack.make(from: transcript, range: TimeRange(start: 100, end: 130), assetID: Fixtures.assetID, style: style, emphasize: false)
        XCTAssertTrue(PlaybookCoach.suggestions(for: timeline, format: .short, rules: rules).contains { $0.id == "caption-pages" })
        timeline.captions?.style.maxWordsPerPage = 3
        XCTAssertFalse(PlaybookCoach.suggestions(for: timeline, format: .short, rules: rules).contains { $0.id == "caption-pages" })

        // On a YouTube edit it's the line length that matters.
        timeline.captions?.style.maxCharsPerLine = 60
        XCTAssertTrue(PlaybookCoach.suggestions(for: timeline, format: .longForm, rules: .standard(for: .longForm)).contains { $0.id == "caption-lines" })
    }

    func testTheCoachCarriesThePlaybookAdviceAndTakesAStylesRules() {
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 200, audio: Fixtures.audio(duration: 200, spikes: [115], silences: []))
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        PunchInGenerator.apply(moments: [.reaction(15)], to: &timeline, trackID: timeline.tracks[0].id)
        XCTAssertTrue(EditCoach.review(timeline, analysis: analysis).suggestions.contains { $0.id == "static-stretch" })
        // Held to a calmer style's rules, the same edit is fine.
        var calm = EditorPlaybook.commentary.rules
        calm.openingStaticStretch = 40
        XCTAssertFalse(EditCoach.review(timeline, analysis: analysis, rules: calm).suggestions.contains { $0.id == "static-stretch" })
        // With no zooms at all the coach says "add zooms" once, not twice.
        let bare = EditCoach.review(Fixtures.simpleTimeline(clipDuration: 30), analysis: analysis).suggestions
        XCTAssertTrue(bare.contains { $0.id == "zooms" })
        XCTAssertFalse(bare.contains { $0.id == "static-stretch" })
    }

    func testAnEditRemembersTheStyleItWasCutInAndIsJudgedByIt() throws {
        let duration: Seconds = 3000
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: Array(stride(from: 150.0, to: 2900, by: 230))),
                                     transcript: Fixtures.transcript(duration: duration), profile: .gameplay)
        let asset = Fixtures.mediaAsset(duration: duration)

        // PULSE's own way carries no style and is held to the standard rules.
        let plain = LongFormEditor.build(asset: asset, analysis: analysis).timeline
        XCTAssertNil(plain.editStyle)
        XCTAssertEqual(EditorPlaybook.rules(for: plain), .standard(for: .longForm))

        // Cut as "Clean commentary": the timeline says so, survives a save, and the calmer rules apply.
        let playbook = EditorPlaybook.commentary
        let options = playbook.style.longFormOptions(.recommended(for: playbook.style))
        let calm = LongFormEditor.build(asset: asset, analysis: analysis, options: options).timeline
        XCTAssertEqual(calm.editStyle, "commentary")
        let saved = try JSONDecoder().decode(Timeline.self, from: JSONEncoder().encode(calm))
        XCTAssertEqual(saved.editStyle, "commentary")
        XCTAssertEqual(EditorPlaybook.rules(for: saved), playbook.rules)
        XCTAssertGreaterThan(EditorPlaybook.rules(for: saved).maxStaticStretch, PacingRules.standard(for: .longForm).maxStaticStretch)

        // A studied reference isn't a playbook, and a project saved before this version has no style.
        var studied = playbook.style
        studied.id = UUID()
        studied.name = "Some video I liked"
        XCTAssertNil(LongFormEditor.build(asset: asset, analysis: analysis, options: studied.longFormOptions(.recommended(for: studied))).timeline.editStyle)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(calm)) as? [String: Any])
        json["editStyle"] = nil
        let old = try JSONDecoder().decode(Timeline.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.editStyle)

        // The energetic style really does cut harder than the calm one.
        let fast = LongFormEditor.build(asset: asset, analysis: analysis,
                                        options: EditorPlaybook.retention.style.longFormOptions(.recommended(for: EditorPlaybook.retention.style))).timeline
        XCTAssertEqual(fast.editStyle, "retention")
        func zooms(_ t: Timeline) -> Int { t.allClips.reduce(0) { $0 + $1.transform.zoom.keyframes.count } }
        XCTAssertGreaterThan(zooms(fast), zooms(calm))
    }
}
