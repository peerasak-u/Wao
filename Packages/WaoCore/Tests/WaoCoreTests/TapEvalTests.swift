@testable import wao_typing_eval
import WaoTyping
import XCTest

/// Guards the shipped model and tuning against a rebuild or retune that quietly stops helping.
final class TapEvalTests: XCTestCase {
    func testDecodingFixesMostSlipsAndBreaksFewTaps() throws {
        let replay = Replay(model: try XCTUnwrap(TypingModel.bundled))
        let lines = try String(contentsOf: Paths.fixtures.appendingPathComponent("typing-holdout-chat.txt"), encoding: .utf8)
            .split(separator: "\n").prefix(60).map(String.init)
        var rng = SplitMix64(seed: 0)
        var tally = Tally(), geometricErrors = 0
        for line in lines {
            let taps = replay.taps(line, rng: &rng) { _ in (0.2, 7) }
            let geometric = replay.decode(taps, with: .geometric), decoded = replay.decode(taps, with: .decoded(.shipped))
            for (i, tap) in taps.enumerated() {
                guard let tap else { continue }
                tally.add(intended: tap.intended, geometric: geometric[i], decoded: decoded[i])
                if geometric[i] != tap.intended { geometricErrors += 1 }
            }
        }
        XCTAssertGreaterThan(tally.taps, 2000)
        XCTAssertLessThanOrEqual(Double(tally.errors), 0.5 * Double(geometricErrors), "\(tally)")
        XCTAssertLessThanOrEqual(tally.induced * 5, tally.fixed, "\(tally)")
    }
}
