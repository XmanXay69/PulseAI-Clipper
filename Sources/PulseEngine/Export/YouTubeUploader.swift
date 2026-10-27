import AppKit
import Foundation
import Network
import PulseCore

/// Signs in to Google and uploads to YouTube (#482): the installed-app OAuth flow with a loopback redirect
/// on 127.0.0.1, then the Data API's resumable upload in 8 MB pieces. Only accounts.google.com,
/// oauth2.googleapis.com and www.googleapis.com are contacted.
public enum YouTubeUploader {
    public struct Credentials: Codable, Sendable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date

        public var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
    }

    public enum PublishError: LocalizedError {
        case signInFailed(String)
        case denied(String)
        case uploadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .signInFailed(let s): return "Google sign-in failed: \(s)"
            case .denied(let s): return "YouTube refused: \(s)"
            case .uploadFailed(let s): return "The upload failed: \(s)"
            }
        }
    }

    // MARK: Sign-in

    /// Opens the browser for consent and waits for Google to send the code back to a loopback port.
    public static func signIn(clientID: String, clientSecret: String?) async throws -> Credentials {
        let (verifier, challenge) = YouTubeOAuth.pkce()
        let state = PhoneReview.token()
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "app.pulse.oauth")
        let box = ContinuationBox()
        let code: String = try await withCheckedThrowingContinuation { continuation in
            box.continuation = continuation
            listener.stateUpdateHandler = { s in
                switch s {
                case .ready:
                    guard let port = listener.port?.rawValue else { return }
                    let redirect = "http://127.0.0.1:\(port)/callback"
                    box.redirectURI = redirect
                    let url = YouTubeOAuth.authorizationURL(clientID: clientID, redirectURI: redirect, state: state, codeChallenge: challenge)
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                case .failed(let error):
                    box.finish(.failure(PublishError.signInFailed(error.localizedDescription)))
                default: break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    let head = String(decoding: data ?? Data(), as: UTF8.self)
                    let path = head.split(separator: "\r\n").first.map(String.init)?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                    let parsed = URL(string: "http://127.0.0.1" + path).flatMap(YouTubeOAuth.parseRedirect)
                    let ok = parsed != nil && parsed?.state == state
                    let page = ok ? "<h2 style='font-family:system-ui'>PULSE is signed in — you can close this tab.</h2>"
                                  : "<h2 style='font-family:system-ui'>Sign-in didn't complete. Go back to PULSE and try again.</h2>"
                    let body = Data(("<!doctype html><meta charset=utf-8>" + page).utf8)
                    let response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                        if ok, let parsed { box.finish(.success(parsed.code)) } else { box.finish(.failure(PublishError.signInFailed("no code came back"))) }
                    })
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 300) { box.finish(.failure(PublishError.signInFailed("timed out waiting for the browser"))) }
            box.listener = listener
        }
        listener.cancel()
        guard let redirectURI = box.redirectURI else { throw PublishError.signInFailed("no redirect address") }
        let body = YouTubeOAuth.tokenRequestBody(clientID: clientID, clientSecret: clientSecret, code: code, redirectURI: redirectURI, verifier: verifier)
        return try await exchange(body)
    }

    /// The sign-in's continuation (resumed once, from whichever of the browser, a listener failure or the
    /// timeout comes first) and the redirect address the browser was sent to.
    private final class ContinuationBox: @unchecked Sendable {
        private var _continuation: CheckedContinuation<String, Error>?
        private var _redirectURI: String?
        private let lock = NSLock()
        var listener: NWListener?

        var continuation: CheckedContinuation<String, Error>? {
            get { lock.lock(); defer { lock.unlock() }; return _continuation }
            set { lock.lock(); _continuation = newValue; lock.unlock() }
        }

        var redirectURI: String? {
            get { lock.lock(); defer { lock.unlock() }; return _redirectURI }
            set { lock.lock(); _redirectURI = newValue; lock.unlock() }
        }

        func finish(_ result: Result<String, Error>) {
            lock.lock()
            let c = _continuation
            _continuation = nil
            lock.unlock()
            guard let c else { return }
            switch result {
            case .success(let v): c.resume(returning: v)
            case .failure(let e): c.resume(throwing: e)
            }
        }
    }

    static func exchange(_ body: Data) async throws -> Credentials {
        var request = URLRequest(url: YouTubeOAuth.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PublishError.signInFailed("unreadable token reply") }
        if let error = json["error"] as? String {
            throw PublishError.signInFailed((json["error_description"] as? String) ?? error)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = json["access_token"] as? String else { throw PublishError.signInFailed("no token in the reply") }
        let expires = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return Credentials(accessToken: access, refreshToken: json["refresh_token"] as? String, expiresAt: Date().addingTimeInterval(expires))
    }

    /// A fresh access token from the refresh token; the refresh token is kept.
    public static func refresh(_ credentials: Credentials, clientID: String, clientSecret: String?) async throws -> Credentials {
        guard let refresh = credentials.refreshToken else { throw PublishError.signInFailed("sign in again (no refresh token)") }
        var fresh = try await exchange(YouTubeOAuth.refreshRequestBody(clientID: clientID, clientSecret: clientSecret, refreshToken: refresh))
        if fresh.refreshToken == nil { fresh.refreshToken = refresh }
        return fresh
    }

    // MARK: Upload

    public static let chunkSize = 8 * 1024 * 1024

    /// Uploads the file with its metadata; returns the video id. `progress` is 0…1 of the bytes sent.
    public static func upload(file: URL, metadata: YouTubeUpload, credentials: Credentials,
                              progress: @escaping @Sendable (Double) -> Void, isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw PublishError.uploadFailed("the file is empty") }
        let notify = metadata.notifySubscribers ? "true" : "false"
        var start = URLRequest(url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status&notifySubscribers=\(notify)")!)
        start.httpMethod = "POST"
        start.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue("\(size)", forHTTPHeaderField: "X-Upload-Content-Length")
        start.httpBody = try metadata.metadataJSON()
        let (startData, startResponse) = try await URLSession.shared.data(for: start)
        guard let http = startResponse as? HTTPURLResponse else { throw PublishError.uploadFailed("no reply") }
        guard http.statusCode == 200, let location = http.value(forHTTPHeaderField: "Location"), let session = URL(string: location) else {
            throw PublishError.denied(Self.message(from: startData, status: http.statusCode))
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var offset: Int64 = 0
        var last: Data = Data()
        var resends = 0
        var recoveries = 0
        while offset < size {
            if isCancelled() { throw EngineError.cancelled }
            try handle.seek(toOffset: UInt64(offset))
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { break }
            let end = offset + Int64(chunk.count) - 1
            var put = URLRequest(url: session)
            put.httpMethod = "PUT"
            put.setValue("video/*", forHTTPHeaderField: "Content-Type")
            put.setValue("bytes \(offset)-\(end)/\(size)", forHTTPHeaderField: "Content-Range")
            put.timeoutInterval = 300
            let data: Data, r: HTTPURLResponse
            do {
                let (d, response) = try await URLSession.shared.upload(for: put, from: chunk)
                guard let http = response as? HTTPURLResponse else { throw PublishError.uploadFailed("no reply") }
                (data, r) = (d, http)
            } catch let error as URLError where recoveries < 5 {
                // The connection dropped mid-piece: ask where the upload got to and carry on from there.
                recoveries += 1
                try await Task.sleep(nanoseconds: UInt64(recoveries) * 2_000_000_000)
                offset = try await resumeOffset(session: session, size: size, fallback: offset, reason: error.localizedDescription)
                continue
            }
            switch r.statusCode {
            case 200, 201:
                last = data
                offset = size
            case 308:
                // "Range: bytes=0-N" says what landed; no Range means nothing did, so the same piece goes again.
                if let n = Self.lastByte(in: r) {
                    offset = n + 1
                    resends = 0
                } else {
                    resends += 1
                    if resends > 3 { throw PublishError.uploadFailed("YouTube kept refusing the same piece of the file") }
                }
            case 401:
                throw PublishError.denied("the sign-in expired — sign in again in Settings → Publishing")
            case 500...504 where recoveries < 5:
                // Google asks for exactly this: wait, query the upload's status, resume from what landed.
                recoveries += 1
                try await Task.sleep(nanoseconds: UInt64(recoveries) * 2_000_000_000)
                offset = try await resumeOffset(session: session, size: size, fallback: offset, reason: Self.message(from: data, status: r.statusCode))
            default:
                throw PublishError.uploadFailed(Self.message(from: data, status: r.statusCode))
            }
            progress(Double(offset) / Double(size))
        }
        guard let json = try? JSONSerialization.jsonObject(with: last) as? [String: Any], let id = json["id"] as? String else {
            throw PublishError.uploadFailed("YouTube didn't return a video id")
        }
        return id
    }

    /// The upload's next byte after an interruption: an empty PUT with "bytes */size" makes YouTube answer with
    /// what it holds (308 + Range), or 200/201 when the whole file already landed. `fallback` when it says nothing.
    static func resumeOffset(session: URL, size: Int64, fallback: Int64, reason: String) async throws -> Int64 {
        var query = URLRequest(url: session)
        query.httpMethod = "PUT"
        query.setValue("bytes */\(size)", forHTTPHeaderField: "Content-Range")
        query.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.upload(for: query, from: Data())
        guard let r = response as? HTTPURLResponse else { throw PublishError.uploadFailed(reason) }
        switch r.statusCode {
        case 200, 201: return size
        case 308: return Self.lastByte(in: r).map { $0 + 1 } ?? 0
        case 404, 410: throw PublishError.uploadFailed("the upload expired (\(reason)) — start it again")
        default: throw PublishError.uploadFailed(Self.message(from: data, status: r.statusCode))
        }
    }

    /// N from "Range: bytes=0-N", nil when the header is missing or malformed.
    static func lastByte(in response: HTTPURLResponse) -> Int64? {
        guard let range = response.value(forHTTPHeaderField: "Range"), let dash = range.lastIndex(of: "-") else { return nil }
        return Int64(range[range.index(after: dash)...].trimmingCharacters(in: .whitespaces))
    }

    static func message(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = json["error"] as? [String: Any],
           let message = error["message"] as? String { return "\(message) (HTTP \(status))" }
        return "HTTP \(status)"
    }
}
