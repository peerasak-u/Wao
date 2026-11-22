import CoreGraphics
import WaoCore
import XCTest

final class CursorTextTests: XCTestCase {
    func testMovingRightOverThaiStepsWholeClusters() {
        var text = CursorText(before: "", after: "ก่า")
        XCTAssertEqual(text.move(by: 1), 2)
        XCTAssertEqual(text.before, "ก่")
        XCTAssertEqual(text.move(by: 1), 1)
        XCTAssertEqual(text.after, "")
    }

    func testMovingLeftNeverSplitsAConsonantFromItsMarks() {
        var text = CursorText(before: "สวัสดี", after: "")
        XCTAssertEqual(text.move(by: -1), -2)
        XCTAssertEqual(text.before, "สวัส")
        XCTAssertEqual(text.after, "ดี")
        XCTAssertEqual(text.move(by: -2), -3)
        XCTAssertEqual(text.before, "ส")
    }

    func testSaraAmStaysWithItsConsonantAndTone() {
        var text = CursorText(before: "", after: "น้ำใจ")
        XCTAssertEqual(text.move(by: 1), 3)
        XCTAssertEqual(text.after, "ใจ")
    }

    func testStopsAtTheEdgeOfTheKnownText() {
        var text = CursorText(before: "ab", after: "c")
        XCTAssertEqual(text.move(by: -5), -2)
        XCTAssertEqual(text.move(by: -1), 0)
        XCTAssertEqual(text.move(by: 9), 3)
    }

    func testAMarkRightAfterTheCursorStaysOnItsSide() {
        var text = CursorText(before: "ก", after: "่า")
        XCTAssertEqual(text.move(by: 1), 1)
        XCTAssertEqual(text.before, "ก่")
    }

    func testUpKeepsTheColumn() {
        var text = CursorText(before: "สวัสดีครับ\nกิน", after: "ข้าว")
        XCTAssertEqual(text.moveLines(by: -1), -("สดีครับ\nกิน".utf16.count))
        XCTAssertEqual(text.before, "สวั")
    }

    func testUpOntoAShorterLineLandsAtItsEnd() {
        var text = CursorText(before: "ab\nabcdef", after: "")
        XCTAssertEqual(text.moveLines(by: -1), -7)
        XCTAssertEqual(text.before, "ab")
    }

    func testDownKeepsTheColumn() {
        var text = CursorText(before: "กิ", after: "นข้าว\nสวัสดี")
        XCTAssertEqual(text.moveLines(by: 1), "นข้าว\nส".utf16.count)
        XCTAssertEqual(text.after, "วัสดี")
        XCTAssertEqual(text.before, "กินข้าว\nส")
    }

    func testDownOntoAShorterLineLandsAtItsEnd() {
        var text = CursorText(before: "abcdef", after: "\nab\ncd")
        XCTAssertEqual(text.moveLines(by: 1), 3)
        XCTAssertEqual(text.after, "\ncd")
    }

    func testSeveralLinesAtOnce() {
        var text = CursorText(before: "a\nb\nc", after: "")
        XCTAssertEqual(text.moveLines(by: -2), -4)
        XCTAssertEqual(text.before, "a")
    }

    func testNoLineThereLeavesTheCursorAlone() {
        var text = CursorText(before: "ab", after: "cd")
        XCTAssertNil(text.moveLines(by: -1))
        XCTAssertNil(text.moveLines(by: 1))
        XCTAssertEqual(text, CursorText(before: "ab", after: "cd"))
        var two = CursorText(before: "a\nb", after: "")
        XCTAssertNil(two.moveLines(by: -2))
        XCTAssertEqual(two.before, "a\nb")
    }

    func testAnEmptyLineIsALine() {
        var text = CursorText(before: "abc\n\nab", after: "")
        XCTAssertEqual(text.moveLines(by: -1), -3)
        XCTAssertEqual(text.before, "abc\n")
    }
}

final class SpaceTrackpadTests: XCTestCase {
    private let key = CGPoint(x: 100, y: 20)

    func testATapTypesASpace() {
        var pad = SpaceTrackpad()
        XCTAssertNil(pad.down(at: key))
        XCTAssertNil(pad.moved(to: CGPoint(x: 103, y: 21), onKey: true))
        XCTAssertEqual(pad.lifted(), .space)
        XCTAssertEqual(pad.phase, .idle)
    }

    func testAHoldTracksAndTypesNothing() {
        var pad = SpaceTrackpad()
        _ = pad.down(at: key)
        XCTAssertEqual(pad.held(), .begin)
        XCTAssertEqual(pad.lifted(), .end)
        XCTAssertEqual(pad.phase, .idle)
    }

    func testMovementBeforeTheHoldDoesNotMoveTheCursor() {
        var pad = SpaceTrackpad()
        _ = pad.down(at: key)
        _ = pad.moved(to: CGPoint(x: 130, y: 20), onKey: true)
        _ = pad.held()
        XCTAssertNil(pad.moved(to: CGPoint(x: 130 + SpaceTrackpad.step.width - 1, y: 20), onKey: true))
        XCTAssertEqual(pad.moved(to: CGPoint(x: 130 + SpaceTrackpad.step.width, y: 20), onKey: true), .move(columns: 1, lines: 0))
    }

    func testTrackingRoamsAnywhereAndKeepsTheRemainder() {
        var pad = SpaceTrackpad()
        let step = SpaceTrackpad.step
        _ = pad.down(at: key)
        _ = pad.held()
        XCTAssertEqual(pad.moved(to: CGPoint(x: key.x - 3.5 * step.width, y: key.y), onKey: false), .move(columns: -3, lines: 0))
        XCTAssertEqual(pad.moved(to: CGPoint(x: key.x - 4 * step.width, y: key.y), onKey: false), .move(columns: -1, lines: 0))
        XCTAssertEqual(pad.moved(to: CGPoint(x: key.x - 4 * step.width, y: key.y - 200), onKey: false),
                       .move(columns: 0, lines: Int(-200 / step.height)))
    }

    func testSlidingOffTheKeyBeforeTheHoldTypesNothing() {
        var pad = SpaceTrackpad()
        _ = pad.down(at: key)
        _ = pad.moved(to: CGPoint(x: 100, y: -60), onKey: false)
        XCTAssertNil(pad.held())
        XCTAssertNil(pad.lifted())
    }

    func testASecondFingerSettlesTheFirst() {
        var pad = SpaceTrackpad()
        _ = pad.down(at: key)
        XCTAssertEqual(pad.down(at: key), .space)
        XCTAssertNil(pad.held())
        XCTAssertNil(pad.lifted())

        _ = pad.down(at: key)
        _ = pad.held()
        XCTAssertEqual(pad.down(at: key), .end)
        XCTAssertNil(pad.moved(to: .zero, onKey: false))
        XCTAssertNil(pad.lifted())
    }

    func testAFingerElsewhereEndsTrackingUntilLift() {
        var pad = SpaceTrackpad()
        _ = pad.down(at: key)
        XCTAssertNil(pad.interrupted())
        _ = pad.held()
        XCTAssertEqual(pad.interrupted(), .end)
        XCTAssertNil(pad.moved(to: .zero, onKey: false))
        XCTAssertNil(pad.lifted())
        XCTAssertEqual(pad.phase, .idle)
    }

    func testACancelledTouchEndsCleanly() {
        var pad = SpaceTrackpad()
        _ = pad.down(at: key)
        XCTAssertNil(pad.cancelled())
        _ = pad.down(at: key)
        _ = pad.held()
        XCTAssertEqual(pad.cancelled(), .end)
        XCTAssertEqual(pad.phase, .idle)
    }
}
