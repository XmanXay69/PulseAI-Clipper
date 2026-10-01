import XCTest
@testable import PulseCore
@testable import PulseEngine

final class TranscriberChoiceTests: XCTestCase {
    func testEnglishOnlyWhisperModelsOnlyCoverEnglish() {
        let english = URL(fileURLWithPath: "/m/ggml-base.en.bin")
        let multilingual = URL(fileURLWithPath: "/m/ggml-large-v3-turbo.bin")
        XCTAssertTrue(TranscriptionEngineFactory.whisperCovers(language: "en-US", model: english))
        XCTAssertTrue(TranscriptionEngineFactory.whisperCovers(language: "en-GB", model: english))
        XCTAssertFalse(TranscriptionEngineFactory.whisperCovers(language: "de-DE", model: english))
        XCTAssertTrue(TranscriptionEngineFactory.whisperCovers(language: "de-DE", model: multilingual))
    }

    func testAutomaticPutsAnExplicitWhisperFirstForEnglish() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-choice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let exe = dir.appendingPathComponent("whisper-cli"), model = dir.appendingPathComponent("ggml-base.en.bin")
        try Data("#!/bin/sh\n".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        try Data().write(to: model)
        var settings = AISettings()
        settings.whisperExecutablePath = exe.path
        settings.whisperModelPath = model.path
        settings.transcriptionLanguage = "en-US"
        XCTAssertEqual(TranscriptionEngineFactory.candidates(settings: settings).first?.id, "whisper.cpp")
        settings.transcriptionLanguage = "fr-FR"
        XCTAssertEqual(TranscriptionEngineFactory.candidates(settings: settings).last?.id, "whisper.cpp")
    }
}
