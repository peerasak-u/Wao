import WaoCore
import XCTest

final class SessionMachineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func run(_ events: [SessionEvent], from state: SessionState = .off) -> (SessionState, [SessionEffect]) {
        events.reduce((state, [SessionEffect]())) { acc, event in
            let (next, effects) = SessionMachine.reduce(acc.0, event)
            return (next, acc.1 + effects)
        }
    }

    func testDictationRoundTrip() {
        let start = Command(kind: .start(.thai))
        let (state, effects) = run([
            .begin(now: t0),
            .command(start, now: t0),
            .command(Command(kind: .stop), now: t0),
            .transcribed(id: start.id, text: "สวัสดี", now: t0 + 2),
        ])
        XCTAssertEqual(state, .done(id: start.id, text: "สวัสดี"))
        XCTAssertEqual(effects, [
            .armIdleTimer(fireAt: t0 + 300), .beginCapture(id: start.id, language: .thai),
            .transcribe(id: start.id, language: .thai), .armIdleTimer(fireAt: t0 + 302),
        ])
    }

    func testStartWithoutSessionDoesNothing() {
        let (state, effects) = run([.command(Command(kind: .start(.thai)), now: t0)])
        XCTAssertEqual(state, .off)
        XCTAssertEqual(effects, [])
    }

    func testCancelWhileListeningDiscardsAudio() {
        let (state, effects) = run([.begin(now: t0), .command(Command(kind: .start(.thai)), now: t0),
                                    .command(Command(kind: .cancel), now: t0 + 1)])
        XCTAssertEqual(state, .idle(expiresAt: t0 + 301))
        XCTAssertEqual(effects.suffix(2), [.discardCapture, .armIdleTimer(fireAt: t0 + 301)])
    }

    func testResultArrivingAfterCancelIsDropped() {
        let start = Command(kind: .start(.thaiEnglishMix))
        let (state, _) = run([
            .begin(now: t0), .command(start, now: t0), .command(Command(kind: .stop), now: t0),
            .command(Command(kind: .cancel), now: t0), .transcribed(id: start.id, text: "late", now: t0),
        ])
        XCTAssertEqual(state, .idle(expiresAt: t0 + 300))
    }

    func testIdleTimeoutReleasesTheMicButNotWhileListening() {
        let listening = run([.begin(now: t0), .command(Command(kind: .start(.thai)), now: t0), .idleTimerFired])
        guard case .listening = listening.0 else { return XCTFail("timer ended a live recording") }
        XCTAssertEqual(run([.begin(now: t0), .idleTimerFired]).0, .off)
        XCTAssertEqual(run([.begin(now: t0), .idleTimerFired]).1.last, .closeMic)
    }

    func testNextUtteranceStartsFromDone() {
        let first = Command(kind: .start(.thai)), second = Command(kind: .start(.thai))
        let (state, _) = run([.begin(now: t0), .command(first, now: t0), .command(Command(kind: .stop), now: t0),
                              .transcribed(id: first.id, text: "a", now: t0), .command(second, now: t0)])
        XCTAssertEqual(state, .listening(id: second.id, language: .thai, heard: nil))
    }

    func testEndAlwaysClosesTheMic() {
        let (state, effects) = run([.begin(now: t0), .command(Command(kind: .start(.thai)), now: t0), .end])
        XCTAssertEqual(state, .off)
        XCTAssertEqual(effects.suffix(2), [.discardCapture, .closeMic])
    }

    func testHeardUpdatesTheRecordingItBelongsTo() {
        let start = Command(kind: .start(.thaiEnglishMix))
        let first = Heard(text: "สวัส", clipped: false), second = Heard(text: "ดีครับ", clipped: true)
        let (state, effects) = run([.begin(now: t0), .command(start, now: t0),
                                    .heard(id: start.id, first), .heard(id: start.id, second)])
        XCTAssertEqual(state, .listening(id: start.id, language: .thaiEnglishMix, heard: second))
        XCTAssertEqual(effects, [.armIdleTimer(fireAt: t0 + 300), .beginCapture(id: start.id, language: .thaiEnglishMix)])
    }

    func testHeardFromAnEarlierRecordingIsDropped() {
        let first = Command(kind: .start(.thaiEnglishMix)), second = Command(kind: .start(.thaiEnglishMix))
        let (state, _) = run([
            .begin(now: t0), .command(first, now: t0), .command(Command(kind: .stop), now: t0),
            .transcribed(id: first.id, text: "a", now: t0), .command(second, now: t0),
            .heard(id: first.id, Heard(text: "late", clipped: false)),
        ])
        XCTAssertEqual(state, .listening(id: second.id, language: .thaiEnglishMix, heard: nil))
    }

    func testHeardAfterStopDoesNotChangeTheState() {
        let start = Command(kind: .start(.thaiEnglishMix))
        let (state, effects) = run([.begin(now: t0), .command(start, now: t0), .command(Command(kind: .stop), now: t0),
                                    .heard(id: start.id, Heard(text: "late", clipped: false))])
        XCTAssertEqual(state, .transcribing(id: start.id))
        XCTAssertEqual(effects.last, .transcribe(id: start.id, language: .thaiEnglishMix))
    }

    func testHeardAfterCancelDoesNotChangeTheState() {
        let start = Command(kind: .start(.thaiEnglishMix))
        let (state, _) = run([.begin(now: t0), .command(start, now: t0), .command(Command(kind: .cancel), now: t0),
                              .heard(id: start.id, Heard(text: "late", clipped: false))])
        XCTAssertEqual(state, .idle(expiresAt: t0 + 300))
    }

    func testBeginAfterAFinishedRecordingReturnsToIdle() {
        let start = Command(kind: .start(.thaiEnglishMix))
        let (state, effects) = run([.begin(now: t0), .command(start, now: t0), .command(Command(kind: .stop), now: t0),
                                    .transcribed(id: start.id, text: "สวัสดี", now: t0 + 2), .begin(now: t0 + 3)])
        XCTAssertEqual(state, .idle(expiresAt: t0 + 303))
        XCTAssertEqual(effects.last, .armIdleTimer(fireAt: t0 + 303))
    }

    func testBeginWhileRecordingDoesNotInterruptIt() {
        let start = Command(kind: .start(.thai))
        let (state, _) = run([.begin(now: t0), .command(start, now: t0), .begin(now: t0 + 1)])
        XCTAssertEqual(state, .listening(id: start.id, language: .thai, heard: nil))
    }
}
