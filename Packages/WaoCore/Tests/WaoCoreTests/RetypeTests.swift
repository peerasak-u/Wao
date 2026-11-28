import CoreGraphics
import WaoTyping
import XCTest

/// Taps typed the way the Thai letters page types them: each decoded on its own, then the latest word retyped.
final class RetypeTests: XCTestCase {
    private let layout = KeyLayout(width: 381, screenWidth: 390, rows: Typing().rows)

    /// The text a keyboard types, and its trail, as the user taps and deletes.
    private struct Typist {
        let model: TypingModel
        let layout: KeyLayout
        var text = ""
        var trail = TouchTrail()

        /// A tap on the centre of the key that types `letter`, shifted where only the shifted layer has it.
        mutating func tap(_ letter: String, interval: TimeInterval) throws {
            let (point, shifted) = try centre(letter)
            try tap(at: point, shifted: shifted, interval: interval)
        }

        /// A tap aimed at `letter` that lands `fraction` of the way to the centre of the key that types `landing`.
        mutating func tap(_ letter: String, slippingToward landing: String, by fraction: CGFloat, interval: TimeInterval) throws {
            let (aim, shifted) = try centre(letter)
            let (hit, _) = try centre(landing)
            try tap(at: CGPoint(x: aim.x + fraction * (hit.x - aim.x), y: aim.y + fraction * (hit.y - aim.y)),
                    shifted: shifted, interval: interval)
        }

        private mutating func tap(at point: CGPoint, shifted: Bool, interval: TimeInterval) throws {
            guard case .character(let key) = model.key(at: point, in: layout, shifted: shifted, before: text, interval: interval)?.kind else {
                return XCTFail("no character at \(point)")
            }
            let typed = key.text(shifted: shifted)
            text += typed
            trail.record(Touch(point: point, interval: interval, shifted: shifted, text: typed))
            if let rewrite = trail.retype(before: text, model: model, layout: layout) { apply(rewrite) }
        }

        mutating func delete() {
            if let rewrite = trail.undoRetype(before: text) { return apply(rewrite) }
            text.unicodeScalars.removeLast()
            trail.deleted(leaving: text)
        }

        private mutating func apply(_ rewrite: Rewrite) {
            var host = text.unicodeScalars
            XCTAssertTrue(rewrite.apply(before: { String(host) }, deleteBackward: { host.removeLast() }, insert: { host += $0.unicodeScalars }))
            text = String(host)
        }

        private func centre(_ letter: String) throws -> (CGPoint, Bool) {
            for key in layout.characterKeys {
                guard case .character(let k) = key.kind else { continue }
                if k.output == letter { return (CGPoint(x: key.cap.midX, y: key.cap.midY), false) }
                if k.shifted == letter { return (CGPoint(x: key.cap.midX, y: key.cap.midY), true) }
            }
            throw XCTSkip("no key types \(letter)")
        }
    }

    private func typist() throws -> Typist { Typist(model: try XCTUnwrap(TypingModel.bundled), layout: layout) }

    /// Taps on the centres of the keys that type `keys`, `interval` seconds apart.
    private func type(_ keys: String, interval: TimeInterval) throws -> String {
        var typist = try typist()
        for scalar in keys.unicodeScalars { try typist.tap(String(scalar), interval: interval) }
        return typist.text
    }

    func testAHurriedTapOnTheKeyBesideTheOneMeantIsRetyped() throws {
        XCTAssertEqual(try type("ไท่รู้", interval: 0.1), "ไม่รู้")
        XCTAssertEqual(try type("ไมา", interval: 0.1), "ไม่")
    }

    func testAHurriedSlipThatStillSpellsWordsIsRetypedToTheOneWordMeant() throws {
        for interval in [0.1, 0.3] {
            var typist = try typist()
            try typist.tap("ข", slippingToward: "บ", by: 0.65, interval: interval)
            XCTAssertEqual(typist.text, "บ", "the slip types บ, and บอบ then คุณ are both words")
            for letter in "อบคุณ".unicodeScalars { try typist.tap(String(letter), interval: interval) }
            XCTAssertEqual(typist.text, "ขอบคุณ", "at \(interval) s")
        }
    }

    func testTheSameTapsMadeSlowlyStayAsTyped() throws {
        XCTAssertEqual(try type("ไท่รู้", interval: 0.6), "ไท่รู้")
        XCTAssertEqual(try type("ไมา", interval: 0.6), "ไมา")
    }

    func testAWordTypedRightIsNeverRetyped() throws {
        for word in ["ไทย", "ท่า", "ไทม์", "ทิม", "ไม่รู้", "สวัสดีครับ", "ขอบคุณมาก"] {
            for interval in [0.1, 0.6] {
                XCTAssertEqual(try type(word, interval: interval), word, "\(word) at \(interval) s")
            }
        }
    }

    func testAMistapAfterShiftIsRetypedFromTheShiftedKeysAround() throws {
        XCTAssertEqual(try type("เศรศฐกิจ", interval: 0.1), "เศรษฐกิจ")
        XCTAssertEqual(try type("บริศัท", interval: 0.1), "บริษัท")
    }

    func testDeleteRightAfterARetypeBringsBackWhatWasTypedAndKeepsIt() throws {
        var typist = try typist()
        for letter in ["ไ", "ม", "า"] { try typist.tap(letter, interval: 0.1) }
        XCTAssertEqual(typist.text, "ไม่")
        typist.delete()
        XCTAssertEqual(typist.text, "ไมา")
        try typist.tap("ก", interval: 0.1)
        XCTAssertTrue(typist.text.hasPrefix("ไมา"), typist.text)
        typist.delete()
        XCTAssertEqual(typist.text, "ไมา")
    }

    func testDeletingBackToTheMistapAndTypingAgainStillRetypes() throws {
        var typist = try typist()
        for letter in ["ไ", "ม", "่", "ร"] { try typist.tap(letter, interval: 0.1) }
        typist.delete()
        typist.delete()
        XCTAssertEqual(typist.text, "ไม")
        try typist.tap("า", interval: 0.1)
        XCTAssertEqual(typist.text, "ไม่")
    }

    func testARewriteLandsWhetherTheHostDeletesAScalarOrAWholeCluster() {
        let rewrite = Rewrite(old: "ท่รู้", new: "ม่รู้")
        var byScalar = "ฉันไท่รู้".unicodeScalars
        XCTAssertTrue(rewrite.apply(before: { String(byScalar) }, deleteBackward: { byScalar.removeLast() }, insert: { byScalar += $0.unicodeScalars }))
        XCTAssertEqual(String(byScalar), "ฉันไม่รู้")
        var byCluster = "ฉันไท่รู้"
        XCTAssertTrue(rewrite.apply(before: { byCluster }, deleteBackward: { byCluster.removeLast() }, insert: { byCluster += $0 }))
        XCTAssertEqual(byCluster, "ฉันไม่รู้")
    }

    func testARewriteLeavesTextItDoesNotMatchAlone() {
        var text = "ฉันไม่รู้"
        var deletes = 0
        XCTAssertFalse(Rewrite(old: "ท่รู้", new: "ม่รู้").apply(before: { text }, deleteBackward: { deletes += 1 }, insert: { text += $0 }))
        XCTAssertEqual(text, "ฉันไม่รู้")
        XCTAssertEqual(deletes, 0)
        var stuck = "ไท่รู้"
        XCTAssertFalse(Rewrite(old: "ท่รู้", new: "ม่รู้").apply(before: { stuck }, deleteBackward: {}, insert: { stuck += $0 }))
        XCTAssertEqual(stuck, "ไท่รู้")
    }
}
