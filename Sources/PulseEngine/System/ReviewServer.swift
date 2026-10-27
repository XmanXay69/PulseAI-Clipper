import AppKit
import Foundation
import Network
import PulseCore

/// A tiny HTTP server for the phone review page (#494): one request per connection, no keep-alive, local
/// network only. The app supplies the items, thumbnails and what Approve / Reject do.
public final class ReviewServer: @unchecked Sendable {
    public let token = PhoneReview.token()
    public var items: @Sendable () async -> [PhoneReview.Item] = { [] }
    public var thumbnail: @Sendable (UUID) async -> CGImage? = { _ in nil }
    public var act: @Sendable (UUID, PhoneReview.Action) async -> Bool = { _, _ in false }
    public var projectName = "PULSE"

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.pulse.review-server")
    private let lock = NSLock()
    private var _port: UInt16?
    private var thumbnailCache: [UUID: Data] = [:]

    public init() {}

    public var port: UInt16? {
        lock.lock(); defer { lock.unlock() }
        return _port
    }

    /// The page's address on the local network, once the listener is up and the Mac has an address.
    public var url: URL? {
        guard let port, let host = LocalNetwork.primaryIPv4() else { return nil }
        return URL(string: "http://\(host):\(port)\(PhoneReview.path(token: token))")
    }

    /// Listens on `preferredPort`, or any free port when that one is taken.
    public func start(preferredPort: UInt16 = 8765) throws {
        stop()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: preferredPort) ?? .any)
        } catch {
            listener = try NWListener(using: params)
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.lock(); self._port = listener.port?.rawValue; self.lock.unlock()
                PulseLog.info("Phone review page on port \(listener.port?.rawValue ?? 0)")
            case .failed(let error):
                PulseLog.warning("Phone review server failed: \(error)")
                self.lock.lock(); self._port = nil; self.lock.unlock()
            default: break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        lock.lock(); _port = nil; thumbnailCache.removeAll(); lock.unlock()
    }

    public var isRunning: Bool { listener != nil }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        var buffer = Data()
        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data { buffer.append(data) }
                if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                    let path = head.split(separator: "\r\n").first.map { String($0) }?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                    Task { await self.respond(to: path, on: connection) }
                } else if isComplete || error != nil || buffer.count > 16_384 {
                    connection.cancel()
                } else {
                    readMore()
                }
            }
        }
        readMore()
    }

    private func respond(to path: String, on connection: NWConnection) async {
        var status = "200 OK", type = "text/html; charset=utf-8", body = Data()
        switch PhoneReview.route(path: path, token: token) {
        case .page:
            body = Data(PhoneReview.html(items: await items(), projectName: projectName, token: token).utf8)
        case .state:
            type = "application/json"
            body = PhoneReview.stateJSON(items: await items())
        case .thumb(let id):
            type = "image/jpeg"
            lock.lock(); let cached = thumbnailCache[id]; lock.unlock()
            if let cached {
                body = cached
            } else if let image = await thumbnail(id), let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                lock.lock(); thumbnailCache[id] = jpeg; lock.unlock()
                body = jpeg
            } else {
                status = "404 Not Found"; type = "text/plain"; body = Data("no thumbnail".utf8)
            }
        case .act(let id, let action):
            type = "application/json"
            let ok = await act(id, action)
            body = Data("{\"ok\": \(ok)}".utf8)
            if !ok { status = "404 Not Found" }
        case nil:
            status = "404 Not Found"; type = "text/plain"; body = Data("not found".utf8)
        }
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// The Mac's address on the local network, for the page's URL and QR code.
public enum LocalNetwork {
    public static func primaryIPv4() -> String? {
        var addresses: [(name: String, address: String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let p = pointer {
            defer { pointer = p.pointee.ifa_next }
            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), (p.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let name = String(cString: p.pointee.ifa_name)
                let address = String(cString: host)
                if !address.hasPrefix("127.") && !address.hasPrefix("169.254.") { addresses.append((name, address)) }
            }
        }
        // Wi-Fi / Ethernet first (en0, en1…), then anything else.
        return (addresses.first { $0.name.hasPrefix("en") } ?? addresses.first)?.address
    }
}
