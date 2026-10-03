import XCTest
@testable import PulseCore

final class AppUpdateTests: XCTestCase {
    func testVersionOrdering() {
        XCTAssertLessThan(AppVersion("1.1.0", build: 80), AppVersion("v1.2.0", build: 1))
        XCTAssertLessThan(AppVersion("1.1.0", build: 80), AppVersion("1.1.0", build: 85), "a rebuild of the same version is newer")
        XCTAssertLessThan(AppVersion("1.9.0"), AppVersion("1.10.0"))
        XCTAssertEqual(AppVersion("v1.1.0-build.92", build: 92), AppVersion("1.1.0", build: 92))
        XCTAssertFalse(AppVersion("1.1.0", build: 80) < AppVersion("1.1.0", build: 80))
        XCTAssertEqual(AppVersion("1.1").description, "1.1.0")
    }

    func testParsesALatestRelease() throws {
        let json = """
        {"tag_name":"v1.1.0","name":"PULSE 1.1.0","draft":false,"prerelease":false,
         "html_url":"https://github.com/XmanXay69/PulseAI-Clipper/releases/tag/v1.1.0",
         "body":"## PULSE 1.1.0\\n\\n### New\\n- Things\\n\\n## Install\\n\\n1. Download\\n\\nBuild 80 from `5bafdaf`",
         "assets":[{"name":"PULSE-1.1.0.dmg","browser_download_url":"https://x/PULSE-1.1.0.dmg","size":10},
                   {"name":"PULSE.dmg","browser_download_url":"https://x/PULSE.dmg","size":149911700},
                   {"name":"PULSE.dmg.sha256","browser_download_url":"https://x/PULSE.dmg.sha256","size":82}]}
        """
        let release = try XCTUnwrap(ReleaseInfo.parse(Data(json.utf8)))
        XCTAssertEqual(release.version, AppVersion("1.1.0", build: 80))
        XCTAssertEqual(release.dmgURL.absoluteString, "https://x/PULSE.dmg")
        XCTAssertEqual(release.checksumURL?.absoluteString, "https://x/PULSE.dmg.sha256")
        XCTAssertEqual(release.sizeBytes, 149911700)
        XCTAssertEqual(release.whatsNew, "## PULSE 1.1.0\n\n### New\n- Things")

        let rebuild = json.replacingOccurrences(of: "\"tag_name\":\"v1.1.0\"", with: "\"tag_name\":\"v1.1.0-build.95\"")
        XCTAssertEqual(ReleaseInfo.parse(Data(rebuild.utf8))?.version.build, 95)
        XCTAssertNil(ReleaseInfo.parse(Data("{\"tag_name\":\"v2\",\"assets\":[]}".utf8)), "no DMG, no update")
    }
}
