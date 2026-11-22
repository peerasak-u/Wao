import CoreGraphics
@testable import WaoTyping
import XCTest

final class KeyLayoutTests: XCTestCase {
    private let widths: [CGFloat] = [390, 393, 440]

    private func pages() -> [(String, [[CharacterKey]])] {
        [("kedmanee", Typing.kedmanee), ("numbers", Typing.numbers)]
    }

    private func row(_ layout: KeyLayout, _ r: Int) -> [PlacedKey] {
        let y = layout.keys.first { $0.id == "\(r).0" }!.cap.midY
        return layout.keys.filter { $0.cap.midY == y }.sorted { $0.cap.minX < $1.cap.minX }
    }

    private func text(_ layout: KeyLayout, at point: CGPoint) -> String? {
        switch layout.key(at: point)?.kind {
        case .character(let key): key.output
        case .shift: "<shift>"
        case .delete: "<delete>"
        case nil: nil
        }
    }

    func testTheThaiRowsAreTwelveEqualCapsSixPointsApartBetweenTheMargins() {
        for width in widths {
            let layout = KeyLayout(width: width, rows: Typing.kedmanee)
            let margin = KeyMetrics(width: width).margin
            for r in 0..<4 {
                let caps = row(layout, r).map(\.cap)
                XCTAssertEqual(caps.count, 12, "row \(r) at \(width)")
                XCTAssertEqual(caps.first!.minX, margin, accuracy: 1e-9)
                XCTAssertEqual(caps.last!.maxX, width - margin, accuracy: 1e-9)
                for (a, b) in zip(caps, caps.dropFirst()) {
                    XCTAssertEqual(b.minX - a.maxX, 6, accuracy: 1e-9)
                    XCTAssertEqual(b.width, a.width, accuracy: 1e-9)
                }
            }
        }
    }

    /// The caps tools/keyboard_parity.py found on the system keyboard, as x and width in points.
    func testCapsSitWhereTheSystemKeyboardDrawsThem() {
        let measured: [(CGFloat, [[CharacterKey]], Int, [(CGFloat, CGFloat)])] = [
            (390, Typing.kedmanee, 0, [(8.7, 25.2), (40.0, 25.3), (356.0, 25.3)]),
            (390, Typing.numbers, 2, [(8.7, 43.0), (65.3, 47.0), (277.7, 47.0), (338.3, 43.3)]),
            (440, Typing.kedmanee, 3, [(6.7, 30.0), (42.7, 30.0), (403.3, 30.3)]),
            (440, Typing.numbers, 2, [(6.7, 50.0), (71.3, 54.7), (314.0, 54.7), (383.3, 50.3)]),
        ]
        for (width, rows, r, expected) in measured {
            let caps = row(KeyLayout(width: width, rows: rows), r).map(\.cap)
            for (x, w) in expected {
                let cap = caps.min { abs($0.minX - x) < abs($1.minX - x) }!
                XCTAssertEqual(cap.minX, x, accuracy: 1, "x of the cap near \(x), row \(r) at \(width)")
                XCTAssertEqual(cap.width, w, accuracy: 1, "width of the cap near \(x), row \(r) at \(width)")
            }
        }
    }

    /// iOS lines space and return up with the third and eighth keys of its QWERTY middle row, nine keys indented by
    /// half a key: x = 27.3 + 37.87 · column at 390 pt, measured.
    func testSpaceAndReturnSitWhereTheSystemKeyboardDrawsThem() {
        let measured: [CGFloat: (space: CGFloat, enter: CGFloat)] = [390: (103.0, 292.4), 440: (114.8, 331.2)]
        for width in widths {
            for rows in [Typing.kedmanee, Typing.numbers] {
                let bottom = KeyLayout(width: width, rows: rows).bottomRow(leading: 2)
                if let x = measured[width] {
                    XCTAssertEqual(bottom.space.cap.minX, x.space, accuracy: 1, "space at \(width)")
                    XCTAssertEqual(bottom.enter.cap.minX, x.enter, accuracy: 1, "return at \(width)")
                }
                XCTAssertEqual(bottom.enter.cap.maxX, width - KeyMetrics(width: width).margin, accuracy: 1e-9)
                XCTAssertEqual(bottom.leading[0].cap.width, bottom.leading[1].cap.width, accuracy: 1e-9)
            }
        }
    }

    func testAnExtraBottomKeyTakesItsRoomFromTheSpaceBar() {
        let layout = KeyLayout(width: 390, rows: Typing.kedmanee)
        let two = layout.bottomRow(leading: 2), three = layout.bottomRow(leading: 3)
        XCTAssertEqual(three.leading[2].cap.width, two.leading[1].cap.width, accuracy: 1e-9)
        XCTAssertEqual(three.space.cap.maxX, two.space.cap.maxX, accuracy: 1e-9)
        XCTAssertEqual(three.enter.cap, two.enter.cap)
        XCTAssertEqual(three.enter.hit.minX, two.enter.hit.minX, accuracy: 1e-9)
    }

    /// Switching page or language never changes the keyboard's height, so the host app does not jump.
    func testEveryPageFillsTheSameHeightBelowTheSameStrip() {
        for width in widths {
            let sizes = Set(pages().map { KeyLayout(width: width, rows: $0.1).size.height })
            XCTAssertEqual(sizes.count, 1, "\(width)")
            XCTAssertEqual(sizes.first! + KeyLayout.stripHeight(width: width), KeyMetrics(width: width).height, accuracy: 1e-9)
        }
        XCTAssertEqual(KeyMetrics(width: 390).height, 245)
        XCTAssertEqual(KeyMetrics(width: 440).height, 253)
    }

    /// iOS 26 gives the extension a 381 pt view centred on a 390 pt screen: caps stay where the screen has them,
    /// touches reach the view's edges and no further.
    func testANarrowViewKeepsTheCapsWhereTheScreenHasThem() {
        let full = KeyLayout(width: 390, rows: Typing.kedmanee)
        let narrow = KeyLayout(width: 381, screenWidth: 390, rows: Typing.kedmanee)
        XCTAssertEqual(narrow.size.width, 381)
        for (a, b) in zip(full.keys, narrow.keys) {
            XCTAssertEqual(b.cap.minX, a.cap.minX - 4.5, accuracy: 1e-9, a.id)
            XCTAssertEqual(b.cap.width, a.cap.width, accuracy: 1e-9, a.id)
            XCTAssertTrue(b.hit.minX >= 0 && b.hit.maxX <= 381, a.id)
        }
        XCTAssertEqual(narrow.key(at: CGPoint(x: 0, y: 1))?.id, "0.0")
        XCTAssertEqual(narrow.key(at: CGPoint(x: 380.9, y: 1))?.id, "0.11")
        let bottom = narrow.bottomRow(leading: 2)
        XCTAssertEqual(bottom.leading[0].hit.minX, 0)
        XCTAssertEqual(bottom.enter.hit.maxX, 381, accuracy: 1e-9)
        XCTAssertEqual(bottom.enter.cap.maxX, 390 - KeyMetrics(width: 390).margin - 4.5, accuracy: 1e-9)
    }

    func testTheLowestThaiCapsReachTheBottomOfTheKeyboard() {
        for width in widths {
            let layout = KeyLayout(width: width, rows: Typing.kedmanee)
            XCTAssertEqual(layout.bottomRow(leading: 2).space.cap.maxY, layout.size.height, accuracy: 1e-9)
        }
    }

    func testEveryPointOnTheKeyRowsTypesTheKeyDrawnThere() {
        for width in widths {
            for (name, rows) in pages() {
                let layout = KeyLayout(width: width, rows: rows)
                for key in layout.keys {
                    XCTAssertEqual(layout.key(at: CGPoint(x: key.cap.midX, y: key.cap.midY))?.id, key.id, "\(name) \(key.id)")
                    XCTAssertTrue(key.hit.contains(key.cap), "\(name) \(key.id)")
                }
                let area = layout.characterArea
                for y in stride(from: 0.0, to: area.maxY, by: 1.7) {
                    for x in stride(from: 0.0, to: width, by: 0.9) {
                        XCTAssertNotNil(text(layout, at: CGPoint(x: x, y: y)), "\(name) (\(x), \(y)) at \(width)")
                    }
                }
            }
        }
        let thai = KeyLayout(width: 390, rows: Typing.kedmanee)
        XCTAssertEqual(text(thai, at: .zero), "ๅ")
        XCTAssertEqual(text(thai, at: CGPoint(x: 389.9, y: 1)), "ช")
        XCTAssertEqual(text(thai, at: CGPoint(x: 0, y: thai.characterArea.maxY - 0.1)), "<shift>")
        XCTAssertEqual(text(thai, at: CGPoint(x: 389.9, y: thai.characterArea.maxY - 0.1)), "<delete>")
    }
}
