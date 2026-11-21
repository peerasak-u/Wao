import CoreGraphics
import WaoCore
import XCTest

final class TapDecoderTests: XCTestCase {
    private let layout = KeyLayout(size: CGSize(width: 390, height: 242), rows: Typing().rows)
    private let fast: TimeInterval = 0.1
    private let slow: TimeInterval = 1

    private func key(_ output: String) -> PlacedKey {
        layout.keys.first { if case .character(let k) = $0.kind { k.output == output } else { false } }!
    }

    /// What a tap types when the context makes `likely` `gap` nats more probable than every other key.
    private func typed(_ point: CGPoint, likely: String, gap: Float, interval: TimeInterval, tuning: TapTuning = .shipped) -> String? {
        let picked = TapDecoder.pick(point, among: layout.characterKeys, hit: layout.key(at: point),
                                     sigma: tuning.sigma(after: interval), tuning: tuning) { key in
            guard case .character(let k) = key.kind else { return -.infinity }
            return k.output == likely ? 0 : -gap
        }
        return switch picked?.kind {
        case .character(let k): k.output
        case .shift: "<shift>"
        case .delete: "<delete>"
        case nil: nil
        }
    }

    func testWithoutContextEveryTapTypesTheKeyUnderIt() {
        var geometric = TapTuning.shipped
        geometric.lambda = 0
        geometric.anchor = 0
        for y in stride(from: 0.13, to: 4 * layout.rowHeight, by: 1.1) {
            for x in stride(from: 0.17, to: 390, by: 0.71) {
                let point = CGPoint(x: x, y: y)
                guard case .character(let under) = layout.key(at: point)?.kind else { continue }
                XCTAssertEqual(typed(point, likely: "ก", gap: 50, interval: fast, tuning: geometric), under.output, "(\(x), \(y))")
            }
        }
    }

    func testATapInTheMiddleOfAKeyTypesThatKeyWhateverTheContext() {
        let ka = key("ก")
        let point = CGPoint(x: ka.cap.midX + 5, y: ka.cap.midY + 5)
        XCTAssertEqual(typed(point, likely: "ด", gap: 20, interval: fast), "ก")
    }

    func testAHurriedTapNearABorderTypesTheKeyTheContextExpects() {
        let ka = key("ก")
        let nearDo = CGPoint(x: ka.hit.maxX - 2, y: ka.cap.midY)
        XCTAssertEqual(typed(nearDo, likely: "ด", gap: 4, interval: fast), "ด")
        XCTAssertEqual(typed(nearDo, likely: "ก", gap: 4, interval: fast), "ก")
    }

    func testADeliberateTapNearABorderTypesTheKeyUnderTheFinger() {
        let ka = key("ก")
        let nearDo = CGPoint(x: ka.hit.maxX - 2, y: ka.cap.midY)
        XCTAssertEqual(typed(nearDo, likely: "ด", gap: 4, interval: slow), "ก")
    }

    func testOnlyTapsNearABorderAreReconsidered() {
        let ka = key("ก")
        let offCentre = CGPoint(x: ka.cap.midX + 8, y: ka.cap.midY)
        XCTAssertFalse(ka.anchor(TapTuning.shipped.anchor).contains(offCentre))
        XCTAssertEqual(typed(offCentre, likely: "ด", gap: 4, interval: fast), "ก")
    }

    func testShiftAndDeleteAreNeverReinterpreted() {
        XCTAssertEqual(typed(CGPoint(x: 31, y: 170), likely: "ผ", gap: 50, interval: fast), "<shift>")
        XCTAssertEqual(typed(CGPoint(x: 359, y: 170), likely: "ฝ", gap: 50, interval: fast), "<delete>")
    }
}
