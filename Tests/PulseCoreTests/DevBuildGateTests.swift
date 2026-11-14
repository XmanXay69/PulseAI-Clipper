import XCTest
@testable import PulseCore

/// The Claude Code choice exists in settings for every build, but only the personal dev build offers it or
/// acts on it. These run in both configurations and expect the opposite in each.
final class DevBuildGateTests: XCTestCase {
    func testThePublicBuildNeitherOffersNorActsOnClaudeCode() {
        var settings = AISettings()
        settings.cloudProvider = .claudeCode
        #if PULSE_DEV
        XCTAssertTrue(CloudProviderKind.isDevBuild)
        XCTAssertTrue(CloudProviderKind.offered.contains(.claudeCode))
        XCTAssertEqual(settings.activeCloudProvider, .claudeCode)
        #else
        XCTAssertFalse(CloudProviderKind.isDevBuild)
        XCTAssertFalse(CloudProviderKind.offered.contains(.claudeCode), "the download must not offer a Claude login")
        XCTAssertEqual(settings.activeCloudProvider, .none, "a setting saved by the dev build means local only here")
        #endif
        XCTAssertEqual(CloudProviderKind.offered.prefix(3), [.none, .anthropic, .openAICompatible])
        // The other choices are untouched.
        settings.cloudProvider = .anthropic
        XCTAssertEqual(settings.activeCloudProvider, .anthropic)
    }

    func testTheChoiceSurvivesBothAppsSharingOneSettingsFile() throws {
        var settings = AISettings()
        settings.cloudProvider = .claudeCode
        settings.claudeCodePath = "~/tools/claude"
        let saved = try JSONEncoder().encode(settings)
        let read = try JSONDecoder().decode(AISettings.self, from: saved)
        XCTAssertEqual(read.cloudProvider, .claudeCode, "the public app keeps what the dev build chose, it just doesn't use it")
        XCTAssertEqual(read.claudeCodePath, "~/tools/claude")
        // Settings written before this existed still load.
        let old = try JSONDecoder().decode(AISettings.self, from: Data("{\"cloudProvider\":\"anthropic\"}".utf8))
        XCTAssertEqual(old.cloudProvider, .anthropic)
        XCTAssertEqual(old.claudeCodePath, "")
    }
}
