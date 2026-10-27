import Foundation

/// What a YouTube upload says about itself (#482): title, description, tags, who can see it and when.
public struct YouTubeUpload: Codable, Hashable, Sendable {
    public enum Privacy: String, Codable, CaseIterable, Sendable {
        case `private`, unlisted, `public`

        public var displayName: String {
            switch self {
            case .private: return "Private"
            case .unlisted: return "Unlisted"
            case .public: return "Public"
            }
        }
    }

    public var title: String
    public var description: String
    public var tags: [String]
    public var privacy: Privacy
    /// Scheduled publish time; YouTube requires the upload to be private until then.
    public var publishAt: Date?
    /// YouTube category: 20 = Gaming, 22 = People & Blogs, 24 = Entertainment.
    public var categoryID: String
    public var madeForKids: Bool
    public var notifySubscribers: Bool

    public init(title: String, description: String = "", tags: [String] = [], privacy: Privacy = .private, publishAt: Date? = nil,
                categoryID: String = "20", madeForKids: Bool = false, notifySubscribers: Bool = true) {
        self.title = title
        self.description = description
        self.tags = tags
        self.privacy = privacy
        self.publishAt = publishAt
        self.categoryID = categoryID
        self.madeForKids = madeForKids
        self.notifySubscribers = notifySubscribers
    }

    public static let titleLimit = 100
    public static let descriptionLimit = 5000
    public static let tagsLimit = 500

    /// A draft from the edit: the first title idea, the share-ready description, the hashtags as tags.
    public static func draft(from timeline: Timeline, projectName: String) -> YouTubeUpload {
        let copy = timeline.copy
        let title = copy?.titles.first(where: { !$0.isEmpty }) ?? (copy?.shortsTitle.isEmpty == false ? copy!.shortsTitle : timeline.name)
        let tags = (copy?.hashtags ?? []).map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }.filter { !$0.isEmpty }
        return YouTubeUpload(title: String(title.prefix(titleLimit)), description: String(ExportSidecar.text(for: timeline, projectName: projectName).prefix(descriptionLimit)),
                             tags: Array(tags.prefix(30)))
    }

    /// What YouTube would refuse; empty = fine.
    public var problems: [String] {
        var out: [String] = []
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { out.append("the title is empty") }
        if trimmed.count > Self.titleLimit { out.append("the title is over \(Self.titleLimit) characters") }
        if title.contains("<") || title.contains(">") { out.append("the title can't contain < or >") }
        if description.count > Self.descriptionLimit { out.append("the description is over \(Self.descriptionLimit) characters") }
        if tags.reduce(0, { $0 + $1.count + ($1.contains(" ") ? 2 : 0) }) > Self.tagsLimit { out.append("the tags add up to more than \(Self.tagsLimit) characters") }
        if let publishAt {
            if privacy != .private { out.append("a scheduled video has to be private until it goes live") }
            if publishAt < Date() { out.append("the publish time is in the past") }
        }
        return out
    }

    /// The `videos.insert` body: snippet and status.
    public func metadataJSON() throws -> Data {
        var snippet: [String: Any] = ["title": title, "description": description, "categoryId": categoryID]
        if !tags.isEmpty { snippet["tags"] = tags }
        var status: [String: Any] = ["privacyStatus": privacy.rawValue, "selfDeclaredMadeForKids": madeForKids]
        if let publishAt { status["publishAt"] = Self.rfc3339.string(from: publishAt) }
        return try JSONSerialization.data(withJSONObject: ["snippet": snippet, "status": status], options: [.sortedKeys])
    }

    public static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

/// Google's OAuth for an installed app (#482): PKCE, the loopback redirect, the token requests. No secret
/// is required for a desktop client, but one is sent when you have it.
public enum YouTubeOAuth {
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let scope = "https://www.googleapis.com/auth/youtube.upload"

    /// A code verifier and its S256 challenge.
    public static func pkce() -> (verifier: String, challenge: String) {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let verifier = String((0..<64).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
        return (verifier, challenge(for: verifier))
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(SHA256.hash(Data(verifier.utf8)))
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func authorizationURL(clientID: String, redirectURI: String, state: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    /// The code and state from the browser's redirect back to the loopback server.
    public static func parseRedirect(_ url: URL) -> (code: String, state: String)? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        return (code, items.first(where: { $0.name == "state" })?.value ?? "")
    }

    public static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }.joined(separator: "&").utf8)
    }

    public static func tokenRequestBody(clientID: String, clientSecret: String?, code: String, redirectURI: String, verifier: String) -> Data {
        var fields = [("client_id", clientID), ("code", code), ("code_verifier", verifier), ("grant_type", "authorization_code"), ("redirect_uri", redirectURI)]
        if let clientSecret, !clientSecret.isEmpty { fields.append(("client_secret", clientSecret)) }
        return formBody(fields)
    }

    public static func refreshRequestBody(clientID: String, clientSecret: String?, refreshToken: String) -> Data {
        var fields = [("client_id", clientID), ("grant_type", "refresh_token"), ("refresh_token", refreshToken)]
        if let clientSecret, !clientSecret.isEmpty { fields.append(("client_secret", clientSecret)) }
        return formBody(fields)
    }
}

/// SHA-256 in plain Swift, so the core stays free of platform crypto frameworks.
public enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    public static func hash(_ message: Data) -> Data {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var bytes = [UInt8](message)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for i in (0..<8).reversed() { bytes.append(UInt8((bitLength >> (UInt64(i) * 8)) & 0xff)) }
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: bytes.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j + 1]) << 16 | UInt32(bytes[j + 2]) << 8 | UInt32(bytes[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        var out = Data()
        for v in h { for i in (0..<4).reversed() { out.append(UInt8((v >> (UInt32(i) * 8)) & 0xff)) } }
        return out
    }

    public static func hex(_ message: Data) -> String { hash(message).map { String(format: "%02x", $0) }.joined() }
}
