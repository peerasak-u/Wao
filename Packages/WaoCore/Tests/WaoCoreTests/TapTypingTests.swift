import CoreGraphics
import WaoCore
import XCTest

/// Taps decoded with the shipped model and tuning, the way the Thai letters page types them.
final class TapTypingTests: XCTestCase {
    private let layout = KeyLayout(width: 390, rows: Typing().rows)

    private func type(_ taps: [(CGPoint, TimeInterval)], after context: String) throws -> String {
        let model = try XCTUnwrap(TypingModel.bundled)
        var typed = ""
        for (point, interval) in taps {
            guard case .character(let key) = model.key(at: point, in: layout, shifted: false, before: context + typed, interval: interval)?.kind else {
                XCTFail("no character at \(point)")
                continue
            }
            typed += key.output
        }
        return typed
    }

    private func centre(_ output: String) -> CGPoint {
        let key = layout.keys.first { if case .character(let k) = $0.kind { k.output == output } else { false } }!
        return CGPoint(x: key.cap.midX, y: key.cap.midY)
    }

    func testRepeatedTapsOnOneKeyTypeItEveryTime() throws {
        XCTAssertEqual(try type(Array(repeating: (centre("ก"), 0.12), count: 4), after: "มา"), "กกกก")
    }

    func testEveryKeyTappedAtItsCentreTypesItself() throws {
        for row in Typing().rows {
            for key in row {
                XCTAssertEqual(try type([(centre(key.output), 0.12)], after: "ก"), key.output)
            }
        }
    }

    func testAHurriedSlipOntoTheNextKeyTypesTheLetterTheWordNeeds() throws {
        let sa = centre("ส"), wo = centre("ว")
        let slip = CGPoint(x: (sa.x + wo.x) / 2 + 2, y: sa.y)
        XCTAssertEqual(try type([(slip, 0.15)], after: "สวั"), "ส")
    }
}
