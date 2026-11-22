import CoreGraphics
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
    static let contextSettle: TimeInterval = 0.15
    static let fullAccessNotice = "เปิด \"อนุญาตการเข้าถึงแบบเต็ม\" ให้เว่าก่อน: การตั้งค่า > ทั่วไป > แป้นพิมพ์ > แป้นพิมพ์ > เว่า"

    @Published private(set) var mode: KeyboardMode = .typing
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

    /// The host's context lags a cursor move (about 50 ms in the simulator), so a drag steps through its own copy
    /// of the text.
    private var cursorText: CursorText?
    private var lastCursorAdjust = Date.distantPast
    private var bridge: Bridge?
    private var stateObserver: DarwinObserver?
    private var levelTimer: Timer?
    private var startTimer: Timer?

    /// The keyboard always opens on the typing layout, as the system keyboard does. With Full Access the mic key
    /// in its bottom row leads to voice; without it there is no mic (App Review 4.4.1).
    func activate() {
        mode = .typing
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
        insert(typing.type(key))
    }

    func refreshContext() {
        context = readContext()
    }

    func beginCursorTracking() {
        cursorText = readCursorText()
        tracksCursor = true
    }

    /// Without the line above or below in view, up and down stop at the start or end of the line.
    func moveCursor(columns: Int, lines: Int) {
        if lines != 0 { stepCursor(forward: lines > 0) { $0.moveLines(by: lines) ?? $0.moveToLineEdge(down: lines > 0) } }
        if columns != 0 { stepCursor(forward: columns > 0) { $0.move(by: columns) } }
    }

    /// The host shows only part of the text, often just the cursor's line. At the edge of the copy, a host that has
    /// caught up with the last move is asked again; when it still shows nothing that way, the cursor is at a line
    /// break the host hides, and one UTF-16 unit crosses it.
    private func stepCursor(forward: Bool, _ move: (inout CursorText) -> Int) {
        guard var text = cursorText else { return }
        var offset = move(&text)
        if offset == 0, Date().timeIntervalSince(lastCursorAdjust) > Self.contextSettle {
            text = readCursorText()
            offset = move(&text)
            if offset == 0, forward ? text.after.isEmpty : text.before.isEmpty {
                offset = forward ? 1 : -1
                text = CursorText(before: "", after: "")
            }
        }
        cursorText = text
        guard offset != 0 else { return }
        adjustCursor(offset)
        lastCursorAdjust = Date()
    }

    func endCursorTracking() {
        guard tracksCursor else { return }
        cursorText = nil
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

    func showTyping() {
        notice = nil
        mode = .typing
    }

    func showVoice() {
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
