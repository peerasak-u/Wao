import Foundation
import WaoCore

/// Everything the keyboard shows. Dictation phases are derived from the app's `state.json`, matched against the
/// utterance this keyboard started, so a stale `done` from an earlier session is never inserted.
enum KeyboardMode: Equatable {
    case voice
    case typing
    case dictation(Dictation)

    struct Dictation: Equatable {
        enum Phase: Equatable {
            /// Start command written; waiting for the app to report `listening`.
            case starting
            case listening
            case transcribing
        }

        let id: UUID
        var phase: Phase
        /// The newest preview, kept through `transcribing` so the words stay on screen until the result lands.
        var heard: Heard?
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    /// How long the app gets to answer a start command before we assume its session is gone.
    static let startTimeout: TimeInterval = 1.5
    static let fullAccessNotice = "เปิด \"อนุญาตการเข้าถึงแบบเต็ม\" ให้เว่าก่อน: การตั้งค่า > ทั่วไป > แป้นพิมพ์ > แป้นพิมพ์ > เว่า"

    @Published var layout: KeyboardLayout = .thai
    @Published var shifted = false
    @Published private(set) var mode: KeyboardMode = .voice
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 24)
    @Published var notice: String?

    var hasFullAccess = false
    @Published var showsGlobe = true
    var insert: (String) -> Void = { _ in }
    var deleteBackward: () -> Void = {}
    var openApp: () -> Bool = { false }

    private var bridge: Bridge?
    private var stateObserver: DarwinObserver?
    private var levelTimer: Timer?
    private var startTimer: Timer?

    /// Without Full Access there is no mic, so the keyboard opens on the typing layout (App Review 4.4.1).
    func activate() {
        mode = hasFullAccess ? .voice : .typing
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

    func showTyping() {
        notice = nil
        mode = .typing
    }

    func showVoice() {
        guard hasFullAccess else {
            notice = Self.fullAccessNotice
            return
        }
        notice = nil
        mode = .voice
    }

    func micTapped() {
        guard hasFullAccess, let bridge else {
            notice = Self.fullAccessNotice
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
            let command = Command(kind: .start(.thaiEnglishMix))
            write(command)
            mode = .dictation(.init(id: command.id, phase: .starting))
            startTimer?.invalidate()
            startTimer = Timer.scheduledTimer(withTimeInterval: Self.startTimeout, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, case .dictation(let dictation) = self.mode, dictation.phase == .starting else { return }
                    self.mode = .voice
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
        finish()
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
        guard case .dictation(var dictation) = mode, let bridge else { return }
        let state: SessionState
        do {
            state = try bridge.readState()
        } catch {
            notice = "อ่านสถานะไม่ได้: \(error)"
            return
        }
        switch state {
        case .listening(let id, _, let heard) where id == dictation.id:
            startTimer?.invalidate()
            dictation.phase = .listening
            dictation.heard = heard ?? dictation.heard
            mode = .dictation(dictation)
            startLevels()
        case .transcribing(let id) where id == dictation.id:
            dictation.phase = .transcribing
            mode = .dictation(dictation)
            stopLevels()
        case .done(let id, let text) where id == dictation.id:
            if text.isEmpty { notice = "ไม่ได้ยินเสียงพูด ลองอีกครั้ง" } else { insert(text) }
            finish()
        case .failed(let id, let reason) where id == dictation.id:
            notice = reason
            finish()
        case .off, .idle:
            if dictation.phase == .starting { return }
            finish()
        default:
            break
        }
    }

    private func finish() {
        mode = .voice
        stopLevels()
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
