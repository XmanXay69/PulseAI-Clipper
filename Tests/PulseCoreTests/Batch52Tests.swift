import XCTest
@testable import PulseCore

final class Batch52Tests: XCTestCase {
    // MARK: #482 — publishing

    func testSHA256AndPKCEMatchKnownVectors() {
        XCTAssertEqual(SHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        // RFC 7636 appendix B.
        XCTAssertEqual(YouTubeOAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let (verifier, challenge) = YouTubeOAuth.pkce()
        XCTAssertEqual(verifier.count, 64)
        XCTAssertEqual(challenge, YouTubeOAuth.challenge(for: verifier))
        XCTAssertFalse(challenge.contains("="))
    }

    func testAuthorizationURLRedirectAndTokenBodies() throws {
        let url = YouTubeOAuth.authorizationURL(clientID: "abc.apps", redirectURI: "http://127.0.0.1:5000/callback", state: "st", codeChallenge: "ch")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(value("client_id"), "abc.apps")
        XCTAssertEqual(value("scope"), YouTubeOAuth.scope)
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("access_type"), "offline")
        XCTAssertEqual(value("redirect_uri"), "http://127.0.0.1:5000/callback")
        let back = try XCTUnwrap(YouTubeOAuth.parseRedirect(URL(string: "http://127.0.0.1:5000/callback?state=st&code=4%2FabcXYZ&scope=x")!))
        XCTAssertEqual(back.code, "4/abcXYZ")
        XCTAssertEqual(back.state, "st")
        XCTAssertNil(YouTubeOAuth.parseRedirect(URL(string: "http://127.0.0.1:5000/callback?error=access_denied")!))
        let body = String(decoding: YouTubeOAuth.tokenRequestBody(clientID: "id", clientSecret: "s e", code: "c/1", redirectURI: "http://127.0.0.1:1/cb", verifier: "v"), as: UTF8.self)
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=c%2F1"))
        XCTAssertTrue(body.contains("client_secret=s%20e"))
        XCTAssertTrue(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A1%2Fcb"))
        let refresh = String(decoding: YouTubeOAuth.refreshRequestBody(clientID: "id", clientSecret: nil, refreshToken: "r"), as: UTF8.self)
        XCTAssertEqual(refresh, "client_id=id&grant_type=refresh_token&refresh_token=r")
    }

    func testUploadDraftValidationAndMetadata() throws {
        var timeline = Timeline.empty(name: "Ranked night", canvas: .vertical1080)
        timeline.copy = ClipCopy(titles: ["Clutch 1v3 with 1 HP", "Backup"], shortsTitle: "Clutch", tiktokCaption: "no way", instagramCaption: "", hashtags: ["#valorant", "clutch"], generatedBy: "test")
        let draft = YouTubeUpload.draft(from: timeline, projectName: "Ranked")
        XCTAssertEqual(draft.title, "Clutch 1v3 with 1 HP")
        XCTAssertEqual(draft.tags, ["valorant", "clutch"])
        XCTAssertEqual(draft.privacy, .private)
        XCTAssertTrue(draft.description.contains("Clutch 1v3"))
        XCTAssertTrue(draft.problems.isEmpty)
        var bad = draft
        bad.title = String(repeating: "x", count: 101)
        bad.privacy = .public
        bad.publishAt = Date().addingTimeInterval(-60)
        let problems = bad.problems
        XCTAssertTrue(problems.contains { $0.contains("over 100") })
        XCTAssertTrue(problems.contains { $0.contains("private until") })
        XCTAssertTrue(problems.contains { $0.contains("in the past") })
        bad.title = "a <b>"
        XCTAssertTrue(bad.problems.contains { $0.contains("< or >") })
        var scheduled = draft
        scheduled.publishAt = Date(timeIntervalSince1970: 1_900_000_000)
        let json = try JSONSerialization.jsonObject(with: scheduled.metadataJSON()) as! [String: Any]
        let snippet = json["snippet"] as! [String: Any], status = json["status"] as! [String: Any]
        XCTAssertEqual(snippet["title"] as? String, "Clutch 1v3 with 1 HP")
        XCTAssertEqual(snippet["categoryId"] as? String, "20")
        XCTAssertEqual((snippet["tags"] as? [String])?.count, 2)
        XCTAssertEqual(status["privacyStatus"] as? String, "private")
        XCTAssertEqual(status["publishAt"] as? String, "2030-03-17T17:46:40Z")
        XCTAssertEqual(status["selfDeclaredMadeForKids"] as? Bool, false)
        // No copy at all: the timeline's name is the title.
        let plain = YouTubeUpload.draft(from: Timeline.empty(name: "Plain", canvas: .vertical1080), projectName: "P")
        XCTAssertEqual(plain.title, "Plain")
        XCTAssertTrue(plain.tags.isEmpty)
    }

    // MARK: #485 — stills to motion

    func testStillMotionAddsAMoveAndPicksMatchingImages() throws {
        var clip = TimelineClip(name: "Still", content: .media(assetID: UUID()), start: 10, sourceDuration: 2.4, role: .graphic)
        let move = StillMotion.apply(to: &clip, move: .pushIn, strength: 0.12)
        XCTAssertEqual(move, .pushIn)
        XCTAssertEqual(clip.transform.zoom.value(at: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(clip.transform.zoom.value(at: 2.4), 1.12, accuracy: 1e-9)
        XCTAssertTrue(clip.transform.zoom.keyframes.allSatisfy(\.aiGenerated))
        StillMotion.apply(to: &clip, move: .panLeft)
        XCTAssertGreaterThan(clip.transform.panX.value(at: 0), clip.transform.panX.value(at: 2.4))
        XCTAssertEqual(clip.transform.panX.keyframes.count, 2, "the push-in's keyframes were replaced")
        // One move per still, cycling.
        XCTAssertEqual(StillMotion.move(seed: 0), .pushIn)
        XCTAssertNotEqual(StillMotion.move(seed: 1), StillMotion.move(seed: 0))
        XCTAssertEqual(StillMotion.move(seed: StillMotion.Move.allCases.count), .pushIn)
        XCTAssertEqual(StillMotion.move(seed: -1), StillMotion.move(seed: StillMotion.Move.allCases.count - 1))
        var photo = MediaAsset(name: "rage quit.png", path: "/tmp/rage.png", kind: .image, role: .graphic)
        photo.tags = ["meme"]
        let other = MediaAsset(name: "sunset.jpg", path: "/tmp/sun.jpg", kind: .image, role: .graphic)
        let video = MediaAsset(name: "rage.mp4", path: "/tmp/rage.mp4", kind: .video)
        XCTAssertEqual(StillMotion.pick(images: [other, photo, video], for: "rage reaction meme", used: [])?.id, photo.id, "a name or tag match wins")
        XCTAssertEqual(StillMotion.pick(images: [other, photo], for: "nothing matches", used: [])?.id, other.id, "else the first spare")
        XCTAssertEqual(StillMotion.pick(images: [other, photo], for: "rage", used: [photo.id])?.id, other.id)
        XCTAssertNil(StillMotion.pick(images: [video], for: "rage", used: []))
        XCTAssertEqual(StillMotion.grabTime(for: 30, duration: 600), 28.5)
        XCTAssertEqual(StillMotion.grabTime(for: 0.5, duration: 600), 0)
        let extras = try JSONDecoder().decode(EditExtras.self, from: Data("{}".utf8))
        XCTAssertFalse(extras.stillMotion)
    }
}
