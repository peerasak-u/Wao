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

    /// After a move iOS often shows only the cursor's line; at its start the text before is just the line break.
    func testALineBreakOpeningTheKnownTextHidesTheLineAbove() {
        var text = CursorText(before: "\nสวั", after: "สดี")
        XCTAssertNil(text.moveLines(by: -1))
        XCTAssertEqual(text, CursorText(before: "\nสวั", after: "สดี"))
    }

    func testALastLineThatMayGoOnIsUnknownPastItsEnd() {
        var text = CursorText(before: "abcdef", after: "\nab")
        XCTAssertNil(text.moveLines(by: 1))
        XCTAssertEqual(text.before, "abcdef")
    }

    func testAnEmptyLineIsALine() {
        var text = CursorText(before: "abc\n\nab", after: "")
        XCTAssertEqual(text.moveLines(by: -1), -3)
        XCTAssertEqual(text.before, "abc\n")
    }
}

/// A host as the iOS 26.4 simulator showed one: the cursor's line, with the line break before it, and nothing more.
private struct Host {
    let text: String
    var cursor: Int
    var reads = 0

    init(_ text: String, cursorAfter prefix: String) {
        self.text = text
        cursor = prefix.utf16.count
    }

    var beforeCursor: String { String(decoding: Array(text.utf16)[..<cursor], as: UTF16.self) }

    var shown: CursorText {
        let before = beforeCursor
        let after = String(decoding: Array(text.utf16)[cursor...], as: UTF16.self)
        return CursorText(before: before.lastIndex(where: \.isNewline).map { String(before[$0...]) } ?? before,
                          after: String(after.prefix { !$0.isNewline }))
    }

    mutating func run(_ commands: [CursorWalk.Command], _ walk: inout CursorWalk) {
        for command in commands {
            switch command {
            case .adjust(let offset): cursor = min(max(cursor + offset, 0), text.utf16.count)
            case .read:
                reads += 1
                run(walk.read(shown), &walk)
            }
        }
    }

    mutating func move(_ walk: inout CursorWalk, columns: Int = 0, lines: Int = 0) {
        run(walk.move(columns: columns, lines: lines), &walk)
    }
}

final class CursorWalkTests: XCTestCase {
    private let text = "สวัสดีครับ\nกินข้าวเย็น\nab"

    func testDownOntoAHiddenLineKeepsTheColumn() {
        var host = Host(text, cursorAfter: "สวั")
        var walk = CursorWalk(host.shown)
        host.move(&walk, lines: 1)
        XCTAssertEqual(host.beforeCursor, "สวัสดีครับ\nกิน")
    }

    func testUpOntoAHiddenLineKeepsTheColumn() {
        var host = Host(text, cursorAfter: "สวัสดีครับ\nกินข้าว")
        var walk = CursorWalk(host.shown)
        host.move(&walk, lines: -1)
        XCTAssertEqual(host.beforeCursor, String("สวัสดีครับ".prefix("กินข้าว".count)))
    }

    func testAShorterLineOnTheWayKeepsTheColumnForTheNext() {
        var host = Host(text, cursorAfter: "สวัสดีค")
        var walk = CursorWalk(host.shown)
        host.move(&walk, lines: 2)
        XCTAssertEqual(host.beforeCursor, text)
        host.move(&walk, lines: -1)
        XCTAssertEqual(host.beforeCursor, "สวัสดีครับ\n" + "กินข้าวเย็น".prefix(5))
        host.move(&walk, lines: -1)
        XCTAssertEqual(host.beforeCursor, "สวัสดีค")
        host.move(&walk, columns: -1)
        host.move(&walk, lines: 1)
        XCTAssertEqual(host.beforeCursor, "สวัสดีครับ\n" + "กินข้าวเย็น".prefix(4))
    }

    func testWithNoLineThereTheCursorStaysPut() {
        var host = Host(text, cursorAfter: "สวัสดีครับ\nกินข้าวเย็น\na")
        var walk = CursorWalk(host.shown)
        host.move(&walk, lines: 1)
        XCTAssertEqual(host.beforeCursor, "สวัสดีครับ\nกินข้าวเย็น\na")
        var top = Host(text, cursorAfter: "สวั")
        walk = CursorWalk(top.shown)
        top.move(&walk, lines: -1)
        XCTAssertEqual(top.beforeCursor, "สวั")
    }

    func testAHostThatShowsNothingLeavesTheCursorAlone() {
        var walk = CursorWalk(CursorText(before: "", after: ""))
        XCTAssertEqual(walk.move(columns: 0, lines: 1), [])
        XCTAssertEqual(walk.move(columns: 0, lines: -1), [])
    }

    func testSidewaysCrossesALineBreakTheHostHides() {
        var host = Host(text, cursorAfter: "สวัสดีค")
        var walk = CursorWalk(host.shown)
        host.move(&walk, columns: 4)
        XCTAssertEqual(host.beforeCursor, "สวัสดีครับ\nกิ")
        host.move(&walk, columns: -3)
        XCTAssertEqual(host.beforeCursor, "สวัสดีครั")
    }

    func testTheEndOfTheTextStopsASidewaysWalk() {
        var host = Host(text, cursorAfter: "สวัสดีครับ\nกินข้าวเย็น\na")
        var walk = CursorWalk(host.shown)
        host.move(&walk, columns: 5)
        XCTAssertEqual(host.beforeCursor, text)
        host.move(&walk, columns: -1)
        XCTAssertEqual(host.beforeCursor, "สวัสดีครับ\nกินข้าวเย็น\na")
    }

    func testMovesWhileTheHostCatchesUpAreKept() {
        var host = Host(text, cursorAfter: "สวั")
        var walk = CursorWalk(host.shown)
        let crossing = walk.move(columns: 0, lines: 1)
        XCTAssertEqual(walk.move(columns: 2, lines: 0), [])
        host.run(crossing, &walk)
        XCTAssertEqual(host.beforeCursor, "สวัสดีครับ\nกินข้า")
    }

    func testWithinTheShownLineNoReadIsNeeded() {
        var host = Host(text, cursorAfter: "สวั")
        var walk = CursorWalk(host.shown)
        host.move(&walk, columns: 3)
        host.move(&walk, columns: -1)
        XCTAssertEqual(host.beforeCursor, "สวัสดี")
        XCTAssertEqual(host.reads, 0)
    }
}

final class SpaceTrackpadTests: XCTestCase {
    private let key = CGPoint(x: 100, y: 20)

    /// Holds space, then drags by `distance` over `duration` in 120 Hz touch samples, `drift` off the straight line
    /// at each fraction of the way. Returns the moves the drag added up to.
    private func drag(_ distance: CGVector, over duration: TimeInterval, on pad: inout SpaceTrackpad,
                      drift: (CGFloat) -> CGVector = { _ in .zero }) -> (columns: Int, lines: Int) {
        let samples = max(1, Int((duration * 120).rounded()))
        var columns = 0, lines = 0
        let origin = lastPoint ?? key
        for i in 1...samples {
            let f = CGFloat(i) / CGFloat(samples)
            let off = drift(f)
            let point = CGPoint(x: origin.x + distance.dx * f + off.dx, y: origin.y + distance.dy * f + off.dy)
            if case .move(let c, let l) = pad.moved(to: point, at: time + duration * Double(f), onKey: false) {
                columns += c
                lines += l
            }
        }
        time += duration
        lastPoint = CGPoint(x: origin.x + distance.dx + drift(1).dx, y: origin.y + distance.dy + drift(1).dy)
        return (columns, lines)
    }

    private var time: TimeInterval = 0
    private var lastPoint: CGPoint?

    private func held() -> SpaceTrackpad {
        var pad = SpaceTrackpad()
        _ = pad.down(at: key)
        _ = pad.held()
        time = 10
        lastPoint = nil
        return pad
    }

    func testATapTypesASpace() {
        var pad = SpaceTrackpad()
        XCTAssertNil(pad.down(at: key))
        XCTAssertNil(pad.moved(to: CGPoint(x: 103, y: 21), at: 0.05, onKey: true))
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
        _ = pad.moved(to: CGPoint(x: 130, y: 20), at: 0.3, onKey: true)
        _ = pad.held()
        lastPoint = CGPoint(x: 130, y: 20)
        time = 1
        XCTAssertEqual(drag(CGVector(dx: 8, dy: 0), over: 0.4, on: &pad).columns, 0)
        XCTAssertEqual(drag(CGVector(dx: 2, dy: 0), over: 0.1, on: &pad).columns, 1)
    }

    /// A thumb sweeping across the keyboard traces an arc. Measured in the simulator, a 200 pt drag that drifted
    /// 40 pt down moved the cursor a line down and then to the start of the line after it.
    func testAHorizontalDragThatDriftsStaysOnItsLine() {
        var pad = held()
        let moved = drag(CGVector(dx: 200, dy: 0), over: 1, on: &pad) { CGVector(dx: 0, dy: 40 * sin($0 * .pi / 2)) }
        XCTAssertEqual(moved.lines, 0)
        XCTAssertGreaterThanOrEqual(moved.columns, 20)
        var back = held()
        XCTAssertEqual(drag(CGVector(dx: -200, dy: 0), over: 1, on: &back) { CGVector(dx: 0, dy: -6 * sin($0 * 9)) }.lines, 0)
    }

    func testADriftingDragWalksAlongItsLineAndNeverJumps() {
        let line = "สวัสดีครับ วันนี้อากาศดีมาก"
        var host = Host(line + "\nกินข้าวเย็น\nab", cursorAfter: "")
        var walk = CursorWalk(host.shown)
        var pad = held()
        let moved = drag(CGVector(dx: 92, dy: 0), over: 3, on: &pad) { CGVector(dx: 0, dy: 40 * $0) }
        host.move(&walk, columns: moved.columns, lines: moved.lines)
        XCTAssertEqual(host.beforeCursor, String(line.prefix(10)))
    }

    func testSlowAndPreciseMovesOneCharacter() {
        var pad = held()
        XCTAssertEqual(drag(CGVector(dx: 10, dy: 0), over: 0.5, on: &pad).columns, 1)
        var left = held()
        XCTAssertEqual(drag(CGVector(dx: -10, dy: 0), over: 0.5, on: &left).columns, -1)
    }

    func testMotionTooSmallForACharacterAddsUp() {
        var pad = held()
        XCTAssertEqual(drag(CGVector(dx: 91, dy: 0), over: 3, on: &pad).columns, 10)
    }

    func testASlowDragAcrossTheKeyboardCrossesALongLine() {
        var pad = held()
        XCTAssertGreaterThanOrEqual(drag(CGVector(dx: -380, dy: 0), over: 3, on: &pad).columns, -60)
        var again = held()
        XCTAssertLessThanOrEqual(drag(CGVector(dx: -380, dy: 0), over: 3, on: &again).columns, -40)
    }

    func testAFastFlickMovesFar() {
        var pad = held()
        XCTAssertGreaterThanOrEqual(drag(CGVector(dx: 150, dy: 0), over: 0.15, on: &pad).columns, 30)
    }

    func testTheSameDistanceGoesFurtherFaster() {
        var slow = held()
        let near = drag(CGVector(dx: 150, dy: 0), over: 3, on: &slow).columns
        var fast = held()
        let far = drag(CGVector(dx: 150, dy: 0), over: 0.15, on: &fast).columns
        XCTAssertEqual(near, 16)
        XCTAssertGreaterThanOrEqual(far, 2 * near)
    }

    func testADeliberateVerticalDragMovesLines() {
        var pad = held()
        XCTAssertEqual(drag(CGVector(dx: 0, dy: -29), over: 0.4, on: &pad).lines, 0)
        XCTAssertEqual(drag(CGVector(dx: 0, dy: -2), over: 0.05, on: &pad).lines, -1)
        XCTAssertEqual(drag(CGVector(dx: 0, dy: -22), over: 0.3, on: &pad).lines, -1)
        XCTAssertEqual(drag(CGVector(dx: 0, dy: 75), over: 0.8, on: &pad).lines, 3)
    }

    func testAWobbleAfterALineMoveDoesNotUndoIt() {
        var pad = held()
        XCTAssertEqual(drag(CGVector(dx: 0, dy: 32), over: 0.4, on: &pad).lines, 1)
        XCTAssertEqual(drag(CGVector(dx: 0, dy: -15), over: 0.2, on: &pad).lines, 0)
        XCTAssertEqual(drag(CGVector(dx: 0, dy: 15), over: 0.2, on: &pad).lines, 0)
    }

    func testAFingerResettlingNeverChangesLine() {
        var pad = held()
        XCTAssertEqual(drag(CGVector(dx: 0, dy: 25), over: 0.3, on: &pad).lines, 0)
        XCTAssertEqual(drag(CGVector(dx: 0, dy: -25), over: 0.3, on: &pad).lines, 0)
    }

    func testSlidingOffTheKeyBeforeTheHoldTypesNothing() {
        var pad = SpaceTrackpad()
        _ = pad.down(at: key)
        _ = pad.moved(to: CGPoint(x: 100, y: -60), at: 0.2, onKey: false)
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
        XCTAssertNil(pad.moved(to: .zero, at: 1, onKey: false))
        XCTAssertNil(pad.lifted())
    }

    func testAFingerElsewhereEndsTrackingUntilLift() {
        var pad = SpaceTrackpad()
        _ = pad.down(at: key)
        XCTAssertNil(pad.interrupted())
        _ = pad.held()
        XCTAssertEqual(pad.interrupted(), .end)
        XCTAssertNil(pad.moved(to: .zero, at: 1, onKey: false))
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
