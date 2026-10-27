import Foundation
import PulseCore

/// Riot's Live Client Data API (#488): League of Legends and TFT serve the running game's events on
/// https://127.0.0.1:2999 with a self-signed certificate. Polled while recording, each new event is stamped
/// on the recording's clock (game time + the offset between the two clocks), so a kill lands to the frame.
public actor RiotLiveClient {
    public static let eventsURL = URL(string: "https://127.0.0.1:2999/liveclientdata/eventdata")!
    public static let statsURL = URL(string: "https://127.0.0.1:2999/liveclientdata/gamestats")!

    private let session: URLSession
    private var seen = Set<Int>()
    /// recording elapsed − game time, learned from gamestats; nil until the game answers.
    private var offset: Seconds?

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        session = URLSession(configuration: config, delegate: LocalTrust(), delegateQueue: nil)
    }

    /// One poll: the events not seen before, on the recording's clock (`elapsed` is the recording time now).
    /// Empty when no game is running.
    public func poll(elapsed: Seconds) async -> [HUDEvent] {
        guard let (statsData, _) = try? await session.data(from: Self.statsURL),
              let stats = try? JSONSerialization.jsonObject(with: statsData) as? [String: Any],
              let gameTime = (stats["gameTime"] as? NSNumber)?.doubleValue else { return [] }
        offset = elapsed - gameTime
        guard let (data, _) = try? await session.data(from: Self.eventsURL),
              let parsed = GameEventLog.parse(data: data), parsed.source == .riotLiveClient,
              let raw = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["Events"] as? [[String: Any]] else { return [] }
        // Match parsed events back to their IDs so each is reported once.
        var fresh: [HUDEvent] = []
        var k = 0
        for e in raw {
            guard let id = (e["EventID"] as? NSNumber)?.intValue else { continue }
            guard GameEventLog.riotEvent(e) != nil else { continue }
            defer { k += 1 }
            guard k < parsed.events.count, !seen.contains(id) else { continue }
            seen.insert(id)
            fresh.append(parsed.events[k])
        }
        return GameEventLog.shift(fresh, by: offset ?? 0)
    }

    /// True when the game client answers on its local port.
    public static func isAvailable() async -> Bool {
        let client = RiotLiveClient()
        return await client.ping()
    }

    func ping() async -> Bool {
        guard let (data, _) = try? await session.data(from: Self.statsURL) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// Accepts the game client's self-signed certificate for 127.0.0.1 only.
    final class LocalTrust: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.host == "127.0.0.1", let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}
