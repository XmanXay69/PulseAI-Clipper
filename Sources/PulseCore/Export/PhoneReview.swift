import Foundation

/// Review the shorts from a phone (#494): PULSE serves one page on the local network with a card per
/// moment — thumbnail, title, score — and Approve / Reject buttons that land straight in the project. The
/// address carries a random token, so only someone who scanned the code can reach it.
public enum PhoneReview {
    public enum Status: String, Codable, Sendable { case new, approved, rejected }
    public enum Action: String, Codable, Sendable { case approve, reject, undo }

    public struct Item: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var subtitle: String
        public var potential: Int
        public var status: Status

        public init(id: UUID, title: String, subtitle: String, potential: Int, status: Status) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.potential = potential
            self.status = status
        }
    }

    public enum Route: Equatable, Sendable {
        case page
        case state
        case thumb(UUID)
        case act(UUID, Action)
    }

    /// Ten letters and digits, unguessable enough for a LAN page.
    public static func token() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<10).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    public static func path(token: String) -> String { "/r/\(token)" }

    /// The route for a request path (with query), or nil when the token doesn't match or the path is unknown.
    public static func route(path: String, token: String) -> Route? {
        let base = Self.path(token: token)
        guard path == base || path.hasPrefix(base + "/") || path.hasPrefix(base + "?") else { return nil }
        var rest = String(path.dropFirst(base.count))
        var query: [String: String] = [:]
        if let q = rest.firstIndex(of: "?") {
            for pair in rest[rest.index(after: q)...].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
            }
            rest = String(rest[..<q])
        }
        switch rest {
        case "", "/": return .page
        case "/state": return .state
        case "/act":
            guard let id = query["id"].flatMap(UUID.init(uuidString:)), let action = query["do"].flatMap(Action.init(rawValue:)) else { return nil }
            return .act(id, action)
        default:
            if rest.hasPrefix("/thumb/") {
                let name = rest.dropFirst("/thumb/".count)
                let stem = name.hasSuffix(".jpg") ? String(name.dropLast(4)) : String(name)
                return UUID(uuidString: stem).map { .thumb($0) }
            }
            return nil
        }
    }

    public static func stateJSON(items: [Item]) -> Data {
        (try? JSONEncoder().encode(items)) ?? Data("[]".utf8)
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The page: cards that refresh themselves from `/state` every few seconds.
    public static func html(items: [Item], projectName: String, token: String) -> String {
        let base = path(token: token)
        let cards = items.map { item -> String in
            """
            <article class="card \(item.status.rawValue)" data-id="\(item.id.uuidString)">
              <img src="\(base)/thumb/\(item.id.uuidString).jpg" alt="">
              <div class="body">
                <div class="row"><span class="score">\(item.potential)</span><h2>\(esc(item.title))</h2></div>
                <p>\(esc(item.subtitle))</p>
                <div class="buttons">
                  <button class="approve" onclick="act('\(item.id.uuidString)','approve')">Approve</button>
                  <button class="reject" onclick="act('\(item.id.uuidString)','reject')">Reject</button>
                  <button class="undo" onclick="act('\(item.id.uuidString)','undo')">Undo</button>
                </div>
                <div class="status"></div>
              </div>
            </article>
            """
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(projectName)) — review</title>
        <style>
          :root { color-scheme: dark; }
          body { margin: 0; background: #0f1115; color: #eef0f4; font: 16px/1.4 -apple-system, system-ui, sans-serif; }
          header { padding: 16px; position: sticky; top: 0; background: #0f1115dd; backdrop-filter: blur(8px); border-bottom: 1px solid #262a33; }
          header h1 { margin: 0; font-size: 17px; } header p { margin: 4px 0 0; color: #9aa1ad; font-size: 13px; }
          main { padding: 12px; display: grid; gap: 12px; }
          .card { background: #171a21; border: 1px solid #262a33; border-radius: 14px; overflow: hidden; }
          .card img { width: 100%; aspect-ratio: 16 / 9; object-fit: cover; background: #000; display: block; }
          .body { padding: 12px; } .row { display: flex; gap: 10px; align-items: center; } h2 { margin: 0; font-size: 16px; }
          .score { background: #ff6d45; color: #fff; border-radius: 999px; padding: 2px 9px; font-weight: 700; font-size: 13px; }
          p { margin: 6px 0 10px; color: #9aa1ad; font-size: 14px; }
          .buttons { display: flex; gap: 8px; } button { flex: 1; padding: 12px; border: 0; border-radius: 10px; font-size: 15px; font-weight: 600; color: #fff; }
          .approve { background: #2fa36b; } .reject { background: #c94c4c; } .undo { background: #2b3040; flex: 0 0 auto; padding: 12px 14px; }
          .card.approved { border-color: #2fa36b; } .card.rejected { border-color: #c94c4c; opacity: .6; }
          .status { font-size: 13px; color: #9aa1ad; min-height: 18px; margin-top: 8px; }
          .card.approved .status::before { content: "Approved ✓"; color: #2fa36b; } .card.rejected .status::before { content: "Rejected"; color: #c94c4c; }
        </style></head>
        <body>
        <header><h1>\(esc(projectName))</h1><p>\(items.count) moments · tap Approve to favourite a short in PULSE, Reject to send it to Maybe later</p></header>
        <main>
        \(cards)
        </main>
        <script>
          async function act(id, what) {
            const r = await fetch('\(base)/act?id=' + id + '&do=' + what); if (!r.ok) return;
            refresh();
          }
          async function refresh() {
            try {
              const items = await (await fetch('\(base)/state')).json();
              for (const item of items) { const el = document.querySelector('[data-id="' + item.id + '"]'); if (el) el.className = 'card ' + item.status; }
            } catch (e) {}
          }
          setInterval(refresh, 5000);
        </script>
        </body></html>
        """
    }
}
