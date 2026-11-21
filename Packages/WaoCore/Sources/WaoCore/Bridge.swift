import Foundation

/// The transcription language, chosen by the keyboard layout in use.
public enum Language: String, Codable, Sendable, CaseIterable {
    case thai = "th-TH"
    case thaiEnglishMix = "th-mix"

    public var promptIndex: Int64 {
        switch self {
        case .thai: 32
        case .thaiEnglishMix: 63
        }
    }
}

/// Written only by the keyboard, to `command.json`.
public struct Command: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case start(Language)
        case stop
        case cancel
    }

    public let id: UUID
    public let kind: Kind
    public let issuedAt: Date

    public init(id: UUID = UUID(), kind: Kind, issuedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.issuedAt = issuedAt
    }
}

/// Written only by the app's `DictationSession`, to `state.json`.
/// The `id` of listening, transcribing, done and failed is the id of the start command.
public enum SessionState: Codable, Equatable, Sendable {
    case off
    case idle(expiresAt: Date)
    case listening(id: UUID, language: Language)
    case transcribing(id: UUID)
    case done(id: UUID, text: String)
    case failed(id: UUID, reason: String)
}

public enum BridgeError: Error, Equatable {
    case malformed(file: String, detail: String)
    case noAppGroup
}

/// Darwin notifications carry no payload; the receiver re-reads the file the sender owns.
public enum BridgeSignal: String, Sendable {
    case command = "com.peerasak.wao.command"
    case state = "com.peerasak.wao.state"

    public func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue as CFString), nil, nil, true)
    }
}

/// The shared App Group directory. Each file has exactly one writer:
/// the keyboard owns `command.json`; the app owns `state.json` and `level`.
public struct Bridge: Sendable {
    public static let appGroup = "group.com.peerasak.wao"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func shared() throws -> Bridge {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw BridgeError.noAppGroup
        }
        return Bridge(directory: url)
    }

    var commandURL: URL { directory.appendingPathComponent("command.json") }
    var stateURL: URL { directory.appendingPathComponent("state.json") }
    var levelURL: URL { directory.appendingPathComponent("level") }

    public func write(_ command: Command) throws {
        try Self.encoder.encode(command).write(to: commandURL, options: .atomic)
    }

    /// `nil` when the keyboard has never written a command.
    public func readCommand() throws -> Command? {
        guard let data = try? Data(contentsOf: commandURL) else { return nil }
        return try Self.parse(Command.self, from: data, file: "command.json")
    }

    public func write(_ state: SessionState) throws {
        try Self.encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    /// `.off` when the app has never written a state.
    public func readState() throws -> SessionState {
        guard let data = try? Data(contentsOf: stateURL) else { return .off }
        return try Self.parse(SessionState.self, from: data, file: "state.json")
    }

    public func writeLevel(_ level: Float) {
        var value = level
        try? Data(bytes: &value, count: MemoryLayout<Float>.size).write(to: levelURL)
    }

    public func readLevel() -> Float {
        guard let data = try? Data(contentsOf: levelURL), data.count == MemoryLayout<Float>.size else { return 0 }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }

    public static func parse<T: Decodable>(_ type: T.Type, from data: Data, file: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BridgeError.malformed(file: file, detail: String(describing: error))
        }
    }

    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
}

/// Calls `handler` on the main thread whenever `signal` is posted by any process.
public final class DarwinObserver {
    private let name: CFString
    private let handler: () -> Void

    public init(_ signal: BridgeSignal, handler: @escaping () -> Void) {
        self.name = signal.rawValue as CFString
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            name, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name), nil)
    }
}
