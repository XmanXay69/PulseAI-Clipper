import Foundation
import PulseCore

/// whisper.cpp ggml models PULSE can download (from the official whisper.cpp Hugging Face repo).
/// Downloading a model is the only network access needed for local transcription; no audio is uploaded.
public struct WhisperModelInfo: Hashable, Identifiable, Sendable {
    public var id: String { fileName }
    public var name: String
    public var fileName: String
    public var sizeMB: Int
    public var note: String

    public var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")! }
    public var localURL: URL { WhisperModelInfo.directory.appendingPathComponent(fileName) }
    public var isInstalled: Bool { FileManager.default.fileExists(atPath: localURL.path) }

    public static var directory: URL { PulseDirectories.ensure(PulseDirectories.applicationSupport.appendingPathComponent("Models", isDirectory: true)) }

    public static let catalog: [WhisperModelInfo] = [
        WhisperModelInfo(name: "Tiny (English)", fileName: "ggml-tiny.en.bin", sizeMB: 75, note: "Fastest, rough on noisy streams"),
        WhisperModelInfo(name: "Base (English)", fileName: "ggml-base.en.bin", sizeMB: 142, note: "Good default for English"),
        WhisperModelInfo(name: "Small (English)", fileName: "ggml-small.en.bin", sizeMB: 466, note: "More accurate, ~3× slower"),
        WhisperModelInfo(name: "Base (multilingual)", fileName: "ggml-base.bin", sizeMB: 142, note: "Other languages"),
        WhisperModelInfo(name: "Large v3 Turbo", fileName: "ggml-large-v3-turbo.bin", sizeMB: 1620, note: "Best accuracy, needs 16 GB+ RAM"),
    ]
}

public enum WhisperModelDownloader {
    /// Downloads a model into `WhisperModelInfo.directory`, reporting 0…1 progress. Resumable by simply retrying.
    public static func download(_ model: WhisperModelInfo, progress: @escaping @Sendable (Double) -> Void,
                                isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> URL {
        if model.isInstalled { return model.localURL }
        try DiskSpace.ensure(Int64(model.sizeMB) * 1_100_000, at: WhisperModelInfo.directory)
        let box = DownloadBox()
        let temp: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.downloadTask(with: model.url) { location, response, error in
                    box.observation?.invalidate()
                    if let error {
                        continuation.resume(throwing: EngineError.downloadFailed("\(model.name): \(error.localizedDescription)"))
                        return
                    }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        continuation.resume(throwing: EngineError.downloadFailed("\(model.name): HTTP \(http.statusCode)"))
                        return
                    }
                    guard let location else {
                        continuation.resume(throwing: EngineError.downloadFailed("\(model.name): no file received"))
                        return
                    }
                    // The system deletes `location` when this handler returns, so move it now.
                    let kept = WhisperModelInfo.directory.appendingPathComponent(model.fileName + ".part")
                    do {
                        try? FileManager.default.removeItem(at: kept)
                        try FileManager.default.moveItem(at: location, to: kept)
                        continuation.resume(returning: kept)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.task = task
                box.observation = task.progress.observe(\.fractionCompleted) { p, _ in
                    progress(p.fractionCompleted)
                    if isCancelled() { task.cancel() }
                }
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
        try? FileManager.default.removeItem(at: model.localURL)
        try FileManager.default.moveItem(at: temp, to: model.localURL)
        return model.localURL
    }

    private final class DownloadBox: @unchecked Sendable {
        var task: URLSessionDownloadTask?
        var observation: NSKeyValueObservation?
    }
}
