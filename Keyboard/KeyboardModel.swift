import Foundation
import WaoCore

/// Everything the keyboard shows. Dictation phases are derived from the app's `state.json`, matched against the
/// utterance this keyboard started, so a stale `done` from an earlier session is never inserted.
enum KeyboardMode: Equatable {
    case typing
    case dictation(Dictation)

    enum Dictation: Equatable {
        /// Start command written; waiting for the app to report `listening`.
        case starting(UUID)
        case listening(UUID)
        case transcribing(UUID)

        var id: UUID {
            switch self {
            case .starting(let id), .listening(let id), .transcribing(let id): id
            }
        }
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    /// How long the app gets to answer a start command before we assume its session is gone.
    static let startTimeout: TimeInterval = 1.5

    @Published var layout: KeyboardLayout = .thai
    @Published var shifted = false
    @Published private(set) var mode: KeyboardMode = .typing
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 24)
    @Published var notice: String?

    var hasFullAccess = false
    var showsGlobe = true
    var insert: (String) -> Void = { _ in }
    var deleteBackward: () -> Void = {}
    var openApp: () -> Bool = { false }

    private var bridge: Bridge?
    private var stateObserver: DarwinObserver?
    private var levelTimer: Timer?
    private var startTimer: Timer?

    func activate() {
        guard hasFullAccess, stateObserver == nil else { return }
        bridge = try? Bridge.shared()
        stateObserver = DarwinObserver(.state) { [weak self] in
            MainActor.assumeIsolated { self?.stateChanged() }
        }
    }

    func deactivate() {
        if case .dictation = mode { send(.cancel) }
        stateObserver = nil
        stopLevels()
    }

    func type(_ key: CharacterKey) {
        insert(key.text(shifted: shifted))
        shifted = false
    }

    func micTapped() {
        guard hasFullAccess, let bridge else {
            notice = "เปิด \"อนุญาตการเข้าถึงแบบเต็ม\" ให้เว่าก่อน: การตั้งค่า > ทั่วไป > แป้นพิมพ์ > แป้นพิมพ์ > เว่า"
            return
        }
        notice = nil
        let isLive: Bool = switch (try? bridge.readState()) ?? .off {
        case .off: false
        case .idle(let expiresAt): expiresAt > Date()
        default: true
        }
        if !isLive {
            launchApp()
        } else {
            let command = Command(kind: .start(layout.language))
            write(command)
            mode = .dictation(.starting(command.id))
            startTimer?.invalidate()
            startTimer = Timer.scheduledTimer(withTimeInterval: Self.startTimeout, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, case .dictation(.starting) = self.mode else { return }
                    self.mode = .typing
                    self.launchApp()
                }
            }
        }
    }

    func confirm() {
        send(.stop)
    }

    func cancel() {
        send(.cancel)
        mode = .typing
        stopLevels()
    }

    private func launchApp() {
        notice = openApp()
            ? "เปิดแอปเว่าเพื่อเริ่มเซสชัน แล้วกลับมาที่นี่แตะไมค์อีกครั้ง"
            : "เปิดแอปเว่า แล้วแตะ \"เริ่มเซสชัน\" จากนั้นกลับมาที่นี่"
    }

    private func send(_ kind: Command.Kind) {
        write(Command(kind: kind))
    }

    private func write(_ command: Command) {
        do {
            try bridge?.write(command)
            BridgeSignal.command.post()
        } catch {
            notice = "ส่งคำสั่งไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    private func stateChanged() {
        guard case .dictation(let dictation) = mode, let bridge else { return }
        let state: SessionState
        do {
            state = try bridge.readState()
        } catch {
            notice = "อ่านสถานะไม่ได้: \(error)"
            return
        }
        switch state {
        case .listening(let id, _) where id == dictation.id:
            startTimer?.invalidate()
            mode = .dictation(.listening(id))
            startLevels()
        case .transcribing(let id) where id == dictation.id:
            mode = .dictation(.transcribing(id))
            stopLevels()
        case .done(let id, let text) where id == dictation.id:
            insert(text)
            mode = .typing
            stopLevels()
        case .failed(let id, let reason) where id == dictation.id:
            notice = reason
            mode = .typing
            stopLevels()
        case .off, .idle:
            if case .starting = dictation { return }
            mode = .typing
            stopLevels()
        default:
            break
        }
    }

    private func startLevels() {
        guard levelTimer == nil else { return }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let bridge = self.bridge else { return }
                self.levels = Array(self.levels.dropFirst()) + [bridge.readLevel()]
            }
        }
    }

    private func stopLevels() {
        levelTimer?.invalidate()
        levelTimer = nil
        levels = Array(repeating: 0, count: levels.count)
    }
}
