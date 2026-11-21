import Foundation

public enum SessionEvent: Equatable, Sendable {
    /// The app opened the mic (it can only do so in the foreground) and the session is live.
    case begin(now: Date)
    case command(Command, now: Date)
    /// A live preview of the utterance `id`; only the current recording takes it.
    case heard(id: UUID, Heard)
    case transcribed(id: UUID, text: String, now: Date)
    case transcriptionFailed(id: UUID, reason: String, now: Date)
    /// The single armed idle timer fired.
    case idleTimerFired
    case end
}

public enum SessionEffect: Equatable, Sendable {
    case closeMic
    case beginCapture
    case discardCapture
    case transcribe(id: UUID, language: Language)
    /// Replaces any previously armed timer.
    case armIdleTimer(fireAt: Date)
}

/// The dictation session's transitions. `DictationSession` applies the effects and is the only writer of
/// the resulting state, so this table is the whole protocol between keyboard and app.
public enum SessionMachine {
    public static let idleTimeout: TimeInterval = 5 * 60

    public static func reduce(_ state: SessionState, _ event: SessionEvent) -> (SessionState, [SessionEffect]) {
        switch (state, event) {
        case (.off, .begin(let now)), (.idle, .begin(let now)):
            return idle(now, [])

        case (.idle, .command(let c, _)), (.done, .command(let c, _)), (.failed, .command(let c, _)):
            guard case .start(let language) = c.kind else { return (state, []) }
            return (.listening(id: c.id, language: language, heard: nil), [.beginCapture])

        case (.listening(let current, let language, _), .heard(let id, let heard)) where current == id:
            return (.listening(id: id, language: language, heard: heard), [])

        case (.listening(let id, let language, _), .command(let c, let now)):
            switch c.kind {
            case .stop: return (.transcribing(id: id), [.transcribe(id: id, language: language)])
            case .cancel: return idle(now, [.discardCapture])
            case .start: return (state, [])
            }

        case (.transcribing, .command(let c, let now)):
            guard c.kind == .cancel else { return (state, []) }
            return idle(now, [])

        case (.transcribing(let current), .transcribed(let id, let text, let now)) where current == id:
            return (.done(id: id, text: text), [.armIdleTimer(fireAt: now + idleTimeout)])
        case (.transcribing(let current), .transcriptionFailed(let id, let reason, let now)) where current == id:
            return (.failed(id: id, reason: reason), [.armIdleTimer(fireAt: now + idleTimeout)])

        case (.idle, .idleTimerFired), (.done, .idleTimerFired), (.failed, .idleTimerFired):
            return (.off, [.closeMic])

        case (.off, .end):
            return (.off, [])
        case (.listening, .end):
            return (.off, [.discardCapture, .closeMic])
        case (_, .end):
            return (.off, [.closeMic])

        default:
            return (state, [])
        }
    }

    private static func idle(_ now: Date, _ effects: [SessionEffect]) -> (SessionState, [SessionEffect]) {
        let expiresAt = now + idleTimeout
        return (.idle(expiresAt: expiresAt), effects + [.armIdleTimer(fireAt: expiresAt)])
    }
}
