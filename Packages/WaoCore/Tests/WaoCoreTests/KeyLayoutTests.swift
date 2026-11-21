import CoreGraphics
import WaoCore
import XCTest

final class KeyLayoutTests: XCTestCase {
    private let layout = KeyLayout(size: CGSize(width: 390, height: 242), rows: Typing().rows)

    private func text(at point: CGPoint) -> String? {
        switch layout.key(at: point)?.kind {
        case .character(let key): key.output
        case .shift: "<shift>"
        case .delete: "<delete>"
        case nil: nil
        }
    }

    /// The numbers the tap-decoding simulation (and so `TapTuning.shipped`) was measured on: an iPhone 15 grid.
    func testMatchesTheSimulatedGeometry() {
        XCTAssertEqual(layout.rowHeight, 48.4, accuracy: 1e-9)
        let first = layout.keys.first { $0.id == "0.0" }!
        XCTAssertEqual(first.cap.midX, 16.25, accuracy: 1e-9)
        XCTAssertEqual(first.cap.midY, 24.2, accuracy: 1e-9)
        XCTAssertEqual(first.cap.width, 27.5, accuracy: 1e-9)
        XCTAssertEqual(first.cap.height, 40.4, accuracy: 1e-9)
        XCTAssertEqual(layout.keys.first { $0.kind == .shift }!.hit.width, 32.5, accuracy: 1e-9)
        XCTAssertEqual(layout.keys.first { $0.id == "3.0" }!.hit.minX, 32.5, accuracy: 1e-9)
    }

    func testEveryPointOnTheKeyRowsTypesTheKeyDrawnThere() {
        XCTAssertEqual(text(at: CGPoint(x: 0, y: 0)), "ๅ")
        XCTAssertEqual(text(at: CGPoint(x: 389.9, y: 47)), "ช")
        XCTAssertEqual(text(at: CGPoint(x: 32.4, y: 130)), "ฟ")
        XCTAssertEqual(text(at: CGPoint(x: 32.5, y: 130)), "ห")
        XCTAssertEqual(text(at: CGPoint(x: 32.4, y: 170)), "<shift>")
        XCTAssertEqual(text(at: CGPoint(x: 32.5, y: 170)), "ผ")
        XCTAssertEqual(text(at: CGPoint(x: 360, y: 190)), "<delete>")
        for y in stride(from: 0.0, to: 4 * layout.rowHeight, by: 1.7) {
            for x in stride(from: 0.0, to: 390, by: 0.9) {
                XCTAssertNotNil(text(at: CGPoint(x: x, y: y)), "(\(x), \(y))")
            }
        }
    }

    func testEachCapSitsInsideItsHitArea() {
        for key in layout.keys {
            XCTAssertTrue(key.hit.contains(key.cap), key.id)
        }
    }
}
