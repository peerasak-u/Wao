import Foundation
import WaoCore
import WaoInference

/// Drives `SessionMachine` and applies its effects. The only writer of `state.json` and `level`.
actor DictationSession {
    struct Snapshot: Sendable {
        var state: SessionState
        var lastResult: Transcription?
    }

    private(set) var state: SessionState = .off
    private var lastResult: Transcription?
    private var transcriber: Transcriber?
    private var idleTimer: Task<Void, Never>?
    private var lastCommandID: UUID?
    private var commandObserver: DarwinObserver?

    private let bridge: Bridge?
    private let capture = AudioCapture()
    private let onChange: @Sendable (Snapshot) -> Void

    init(bridge: Bridge?, onChange: @escaping @Sendable (Snapshot) -> Void) {
        self.bridge = bridge
        self.onChange = onChange
        try? bridge?.write(SessionState.off)
        bridge?.writeLevel(0)
    }

    func listenForKeyboard() {
        guard commandObserver == nil else { return }
        commandObserver = DarwinObserver(.command) { [weak self] in
            Task { await self?.receiveCommandFile() }
        }
        capture.onLevel = { [bridge] level in bridge?.writeLevel(level) }
        capture.onLimit = { [weak self] in
            Task { await self?.send(.command(Command(kind: .stop), now: Date())) }
        }
    }

    func use(_ transcriber: Transcriber?) {
        self.transcriber = transcriber
    }

    /// Opens the mic. Must be called while the app is in the foreground; iOS refuses to start recording otherwise.
    func begin() throws {
        guard transcriber != nil else { throw SessionError.modelNotLoaded }
        if !capture.isRunning { try capture.start() }
        // A command left over from before this session must not start a recording.
        lastCommandID = (try? bridge?.readCommand())?.id
        send(.begin(now: Date()))
    }

    func end() {
        send(.end)
    }

    /// The in-app test panel drives the same state machine without going through the keyboard's file.
    func sendLocal(_ kind: Command.Kind) {
        send(.command(Command(kind: kind), now: Date()))
    }

    func transcribe(file url: URL, language: Language) throws -> Transcription {
        guard let transcriber else { throw SessionError.modelNotLoaded }
        let result = try transcriber.transcribe(try AudioFile.load16kMono(url), language: language)
        lastResult = result
        onChange(Snapshot(state: state, lastResult: result))
        return result
    }

    private func receiveCommandFile() {
        guard let command = try? bridge?.readCommand(), command.id != lastCommandID else { return }
        lastCommandID = command.id
        send(.command(command, now: Date()))
    }

    private func send(_ event: SessionEvent) {
        let (next, effects) = SessionMachine.reduce(state, event)
        if next != state {
            state = next
            try? bridge?.write(next)
            BridgeSignal.state.post()
            onChange(Snapshot(state: next, lastResult: lastResult))
        }
        effects.forEach(apply)
    }

    private func apply(_ effect: SessionEffect) {
        switch effect {
        case .closeMic:
            idleTimer?.cancel()
            capture.stop()
            bridge?.writeLevel(0)
        case .beginCapture:
            idleTimer?.cancel()
            capture.beginUtterance()
        case .discardCapture:
            _ = capture.endUtterance()
            bridge?.writeLevel(0)
        case .transcribe(let id, let language):
            let audio = capture.endUtterance()
            bridge?.writeLevel(0)
            guard let transcriber else {
                send(.transcriptionFailed(id: id, reason: SessionError.modelNotLoaded.localizedDescription, now: Date()))
                return
            }
            Task.detached(priority: .userInitiated) { [weak self] in
                let event: SessionEvent
                do {
                    let result = try transcriber.transcribe(audio, language: language)
                    await self?.record(result)
                    event = .transcribed(id: id, text: result.text, now: Date())
                } catch {
                    event = .transcriptionFailed(id: id, reason: String(describing: error), now: Date())
                }
                await self?.send(event)
            }
        case .armIdleTimer(let fireAt):
            idleTimer?.cancel()
            idleTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, fireAt.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                await self?.send(.idleTimerFired)
            }
        }
    }

    private func record(_ result: Transcription) {
        lastResult = result
    }
}

enum SessionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "ยังไม่ได้โหลดโมเดล (Model not loaded)"
        }
    }
}
