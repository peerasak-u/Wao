import CoreGraphics
import Foundation
import WaoCore

/// Everything the keyboard shows. Dictation phases are derived from the app's `state.json`, matched against the
/// utterance this keyboard started, so a stale `done` from an earlier session is never inserted.
enum KeyboardMode: Equatable {
    case typing
    case dictation(Dictation)

    struct Dictation: Equatable {
        enum Phase: Equatable {
            /// The app ignores a start while it transcribes, so the start waits for the pending utterance's text.
            case queued
            /// Start command written; waiting for the app to report `listening`.
            case starting
            case listening
        }

        let id: UUID
        var phase: Phase
        var heard: Heard?
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    /// How long the app gets to answer a start command before we assume its session is gone.
    static let startTimeout: TimeInterval = 1.5
    static let contextSettle: TimeInterval = 0.15
    /// The host's text caught up with a cursor move within 25 ms in the iOS 26.4 simulator.
    static let cursorSettle: TimeInterval = 0.06
    static let fullAccessNotice = "เปิด \"อนุญาตการเข้าถึงแบบเต็ม\" ให้เว่าก่อน: การตั้งค่า > ทั่วไป > แป้นพิมพ์ > แป้นพิมพ์ > เว่า"

    @Published private(set) var mode: KeyboardMode = .typing
    /// The utterance the user confirmed, whose text is still being transcribed. ✓ returns to typing at once, so
    /// this outlives the dictation view; its `done` is inserted wherever the cursor is then.
    @Published private(set) var pending: UUID?
    @Published var typing = Typing()
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 24)
    @Published var notice: String?
    /// The text before the cursor as the host last reported it: what tap decoding and suggestions read.
    @Published private(set) var context = ""
    /// Space is held and the keyboard is a trackpad for the cursor.
    @Published private(set) var tracksCursor = false

    var hasFullAccess = false
    @Published var showsGlobe = true
    /// iOS 26 gives the keyboard a view a little narrower than the screen; the system keyboard's caps span the screen.
    var screenWidth: CGFloat?
    var insert: (String) -> Void = { _ in }
    var deleteBackward: () -> Void = {}
    /// Moves the host's cursor by this many UTF-16 units.
    var adjustCursor: (Int) -> Void = { _ in }
    var readContext: () -> String = { "" }
    var readCursorText: () -> CursorText = { CursorText(before: "", after: "") }
    var openApp: () -> Bool = { false }

    private var cursorWalk: CursorWalk?
    private var bridge: Bridge?
    private var stateObserver: DarwinObserver?
    private var levelTimer: Timer?
    private var startTimer: Timer?

    /// The keyboard always opens on the typing layout, as the system keyboard does. With Full Access the mic key
    /// in its bottom row starts dictation; without it there is no mic (App Review 4.4.1).
    func activate() {
        mode = .typing
        guard hasFullAccess, stateObserver == nil else { return }
        bridge = try? Bridge.shared()
        stateObserver = DarwinObserver(.state) { [weak self] in
            MainActor.assumeIsolated { self?.stateChanged() }
        }
    }

    /// The host's field is gone, so text still on its way has nowhere to land.
    func deactivate() {
        if pending != nil || mode != .typing { send(.cancel) }
        pending = nil
        mode = .typing
        startTimer?.invalidate()
        stateObserver = nil
        stopLevels()
    }

    func type(_ key: CharacterKey) {
        insert(typing.type(key))
    }

    func refreshContext() {
        context = readContext()
    }

    func beginCursorTracking() {
        cursorWalk = CursorWalk(readCursorText())
        tracksCursor = true
    }

    func moveCursor(columns: Int, lines: Int) {
        perform(cursorWalk?.move(columns: columns, lines: lines) ?? [])
    }

    private func perform(_ commands: [CursorWalk.Command]) {
        for command in commands {
            switch command {
            case .adjust(let offset):
                adjustCursor(offset)
            case .read:
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.cursorSettle) { [weak self] in
                    guard let self else { return }
                    perform(cursorWalk?.read(readCursorText()) ?? [])
                }
            }
        }
    }

    func endCursorTracking() {
        guard tracksCursor else { return }
        cursorWalk = nil
        tracksCursor = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.contextSettle) { [weak self] in self?.refreshContext() }
    }

    /// The character key a touch on the key rows types, or `nil` when it ended on shift or delete.
    func resolve(_ point: CGPoint, in layout: KeyLayout, interval: TimeInterval) -> PlacedKey? {
        let key = if typing.decodes, let model = TypingModel.bundled {
            model.key(at: point, in: layout, shifted: typing.shifted, before: context, interval: interval)
        } else {
            layout.key(at: point)
        }
        guard case .character = key?.kind else { return nil }
        return key
    }

    var completions: [Completion] {
        guard typing.decodes, let model = TypingModel.bundled else { return [] }
        return model.completions(after: context)
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
        } else if pending != nil {
            mode = .dictation(.init(id: UUID(), phase: .queued))
        } else {
            start(UUID())
        }
    }

    private func start(_ id: UUID) {
        write(Command(id: id, kind: .start(.thaiEnglishMix)))
        mode = .dictation(.init(id: id, phase: .starting))
        startTimer?.invalidate()
        startTimer = Timer.scheduledTimer(withTimeInterval: Self.startTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, case .dictation(let dictation) = self.mode, dictation.phase == .starting else { return }
                // The app may still act on the start once it wakes; nobody would be left to stop it.
                self.send(.cancel)
                self.finish()
                self.launchApp()
            }
        }
    }

    func confirm() {
        guard case .dictation(let dictation) = mode, dictation.phase == .listening else { return }
        send(.stop)
        pending = dictation.id
        finish()
    }

    /// A queued start was never sent, so there is nothing to tell the app.
    func cancel() {
        if case .dictation(let dictation) = mode, dictation.phase != .queued { send(.cancel) }
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
        guard let bridge else { return }
        let state: SessionState
        do {
            state = try bridge.readState()
        } catch {
            notice = "อ่านสถานะไม่ได้: \(error)"
            return
        }
        if let pending { settle(pending, by: state) }
        guard case .dictation(var dictation) = mode else { return }
        switch state {
        case .listening(let id, _, let heard) where id == dictation.id:
            startTimer?.invalidate()
            dictation.phase = .listening
            dictation.heard = heard ?? dictation.heard
            mode = .dictation(dictation)
            startLevels()
        case .off, .idle:
            if dictation.phase == .listening { finish() }
        default:
            break
        }
    }

    /// Inserts the pending utterance's text once the app reports it, then sends a start that was waiting on it.
    private func settle(_ id: UUID, by state: SessionState) {
        switch state {
        case .done(id, let text):
            if text.isEmpty { notice = "ไม่ได้ยินเสียงพูด ลองอีกครั้ง" } else { insert(text) }
        case .failed(id, let reason):
            notice = reason
        case .listening(id, _, _), .transcribing(id):
            // A preview can land before the app reads the stop.
            return
        default:
            // The session ended or another keyboard took it over: the text will not come.
            notice = "ถอดเสียงไม่สำเร็จ ลองอีกครั้ง"
        }
        pending = nil
        if case .dictation(let dictation) = mode, dictation.phase == .queued { start(dictation.id) }
    }

    private func finish() {
        mode = .typing
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
