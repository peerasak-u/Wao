import Foundation
import Network

/// A local stand-in for Hugging Face: `/resolve/<name>` redirects to a signed `/cdn/<name>?Expires=` URL that
/// serves byte ranges slowly enough to interrupt, and refuses once it has expired.
final class RangeServer: @unchecked Sendable {
    struct Request: Equatable {
        let path: String
        let rangeStart: UInt64?
    }

    let port: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "RangeServer")
    private let files: [String: Data]
    private let expiresIn: TimeInterval
    private var log: [Request] = []

    init(files: [String: Data], expiresIn: TimeInterval) throws {
        self.files = files
        self.expiresIn = expiresIn
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        var serve: (NWConnection) -> Void = { _ in }
        listener.newConnectionHandler = { serve($0) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else {
            throw URLError(.cannotConnectToHost)
        }
        self.port = port
        serve = { [unowned self] connection in
            connection.start(queue: queue)
            receiveHead(connection, buffer: Data())
        }
    }

    deinit { listener.cancel() }

    var requests: [Request] { queue.sync { log } }

    func url(_ name: String) -> URL { URL(string: "http://127.0.0.1:\(port)/resolve/\(name)")! }

    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, done, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                respond(connection, head: String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
            } else if done || error != nil {
                connection.cancel()
            } else {
                receiveHead(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        var lines = head.components(separatedBy: "\r\n")
        let target = lines.removeFirst().split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let components = URLComponents(string: target)
        let path = components?.path ?? target
        let rangeStart = headers["range"].flatMap { value -> UInt64? in
            guard value.hasPrefix("bytes="), value.hasSuffix("-") else { return nil }
            return UInt64(value.dropFirst("bytes=".count).dropLast())
        }
        log.append(Request(path: path, rangeStart: rangeStart))

        let name = path.components(separatedBy: "/").last ?? ""
        if path.hasPrefix("/resolve/") {
            let expires = Int(Date().timeIntervalSince1970 + expiresIn)
            send(connection, status: "302 Found", headers: ["Location": "http://127.0.0.1:\(port)/cdn/\(name)?Expires=\(expires)"])
            return
        }
        guard path.hasPrefix("/cdn/"), let file = files[name] else { return send(connection, status: "404 Not Found") }
        let expires = components?.queryItems?.first { $0.name == "Expires" }?.value.flatMap(TimeInterval.init) ?? 0
        guard expires > Date().timeIntervalSince1970 else { return send(connection, status: "403 Forbidden") }

        let etag = "\"\(name)-v1\""
        var start = rangeStart ?? 0
        if let ifRange = headers["if-range"], ifRange != etag { start = 0 }
        var responseHeaders = ["ETag": etag, "Accept-Ranges": "bytes", "Last-Modified": "Mon, 02 Nov 2026 00:00:00 GMT"]
        if start > 0 {
            responseHeaders["Content-Range"] = "bytes \(start)-\(file.count - 1)/\(file.count)"
        }
        send(connection, status: start > 0 ? "206 Partial Content" : "200 OK", headers: responseHeaders,
             body: Data(file[Int(start)...]))
    }

    private func send(_ connection: NWConnection, status: String, headers: [String: String] = [:], body: Data = Data()) {
        var head = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (key, value) in headers { head += "\(key): \(value)\r\n" }
        connection.send(content: Data((head + "\r\n").utf8), completion: .contentProcessed { _ in })
        sendBody(connection, body, from: 0)
    }

    private func sendBody(_ connection: NWConnection, _ body: Data, from offset: Int) {
        guard offset < body.count else {
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let end = min(offset + 32 << 10, body.count)
        connection.send(content: body.subdata(in: offset..<end), completion: .contentProcessed { [self] error in
            if error != nil { return connection.cancel() }
            queue.asyncAfter(deadline: .now() + .milliseconds(5)) { self.sendBody(connection, body, from: end) }
        })
    }
}
