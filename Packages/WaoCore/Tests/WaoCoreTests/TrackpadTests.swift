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

/// A host that cuts what it shows the way the hosts in the iOS 26.4 simulator did (build/verify-evidence/trackpad-v3).
/// Adjusts past either end of the text are clamped, reads can lag the adjusts, and an adjust can be dropped.
private struct CuttingHost {
    enum Cut {
        /// Messages and UITextView: the sentence before the cursor's and the cursor's own up to it, then the rest of
        /// the cursor's sentence up to its line break. A sentence ends after `.`, `?` or `!` and the spaces after it,
        /// so Thai text runs on. At most 300 UTF-16 units a side.
        case sentences
        /// Safari: about this many characters before the cursor, from a word start, and the rest of the sentence after.
        case limited(Int)
    }

    let text: String
    let cut: Cut
    /// Reads show the cursor as it was this many adjusts ago.
    var lag = 0
    /// The adjust, counted from 0, that the host drops.
    var drops: Int?
    /// As Safari did: an adjust counts caret stops, not UTF-16 units. Each character is a stop, and a SARA AM after
    /// other marks is one more: น้ำ is น้ then ำ.
    var countsCaretStops = false
    private(set) var cursor: Int
    private var history: [Int]
    private(set) var splitACharacter = false

    init(_ text: String, _ cut: Cut, cursorAfter characters: Int, lag: Int = 0) {
        self.text = text
        self.cut = cut
        self.lag = lag
        cursor = text.prefix(characters).utf16.count
        history = [cursor]
    }

    /// Characters before the cursor, or nil when it sits inside one.
    var column: Int? {
        let units = Array(text.utf16)
        let before = String(decoding: units[..<cursor], as: UTF16.self)
        let after = String(decoding: units[cursor...], as: UTF16.self)
        return before.count + after.count == text.count ? before.count : nil
    }

    mutating func adjust(_ offset: Int) {
        defer { history.append(cursor) }
        if drops == history.count - 1 { return }
        if countsCaretStops {
            let stops = caretStops
            var at = stops.lastIndex { $0 <= cursor } ?? 0
            if offset < 0, stops[at] < cursor { at += 1 }
            cursor = stops[min(max(at + offset, 0), stops.count - 1)]
        } else {
            cursor = min(max(cursor + offset, 0), text.utf16.count)
        }
        if column == nil { splitACharacter = true }
    }

    /// Where Safari's caret can stop, in UTF-16 units.
    private var caretStops: [Int] {
        var stops = [0]
        var at = 0
        for character in text {
            let scalars = character.unicodeScalars
            if let am = scalars.dropFirst().firstIndex(of: "\u{0E33}") {
                stops.append(at + scalars[..<am].reduce(0) { $0 + $1.utf16.count })
            }
            at += character.utf16.count
            stops.append(at)
        }
        return stops
    }

    /// What a read shows now, `lag` adjusts behind.
    var shown: CursorText { shown(at: history[max(0, history.count - 1 - lag)]) }

    func shown(at cursor: Int) -> CursorText {
        let units = Array(text.utf16)
        let all = Array(String(decoding: units[..<cursor], as: UTF16.self)) + Array(String(decoding: units[cursor...], as: UTF16.self))
        let at = String(decoding: units[..<cursor], as: UTF16.self).count
        func endsSentence(_ i: Int) -> Bool {
            guard i > 0, all[i - 1] == " " || all[i - 1].isNewline else { return false }
            var j = i - 1
            while j > 0, all[j] == " " || all[j].isNewline { j -= 1 }
            return ".?!".contains(all[j])
        }
        func sentenceStart(_ i: Int) -> Int {
            var i = i
            while i > 0, !endsSentence(i) { i -= 1 }
            return i
        }
        var start: Int
        switch cut {
        case .sentences:
            let own = sentenceStart(at)
            start = own > 0 ? sentenceStart(own - 1) : 0
        case .limited(let count):
            start = max(0, at - count)
            while start > 0, start < at, !all[start - 1].isWhitespace { start += 1 }
        }
        var end = at
        while end < all.count, !all[end].isNewline, end == at || !endsSentence(end) { end += 1 }
        let before = Array(String(all[start..<at]).utf16).suffix(300)
        let after = Array(String(all[at..<end]).utf16).prefix(300)
        return CursorText(before: String(decoding: before, as: UTF16.self), after: String(decoding: after, as: UTF16.self))
    }

    mutating func run(_ commands: [CursorWalk.Command], _ walk: inout CursorWalk) {
        for command in commands {
            switch command {
            case .adjust(let offset): adjust(offset)
            case .read: run(walk.read(shown), &walk)
            }
        }
    }

    /// The finger moves `steps` times by `columns` and `lines`.
    mutating func drag(_ walk: inout CursorWalk, columns: Int = 0, lines: Int = 0, steps: Int = 1) {
        for _ in 0..<steps { run(walk.move(columns: columns, lines: lines), &walk) }
    }
}

final class RealHostTests: XCTestCase {
    /// One paragraph, as typed in Messages: sentences end in English, run on in Thai.
    private let paragraph = (0..<8).map { i in
        ["S0\(i) สวัสดีครับ วันนี้อากาศดีมาก", "S0\(i) กินข้าวกันไหมครับ", "S0\(i) ผมชอบน้ำใจของคนไทย", "S0\(i) พรุ่งนี้จะไปเที่ยวเชียงใหม่"][i % 4]
            + [" The quick brown fox jumps over the lazy dog.", " Meet me at 10 am near the station.", " Keyboards should feel smooth."][i % 3]
    }.joined(separator: " ")

    /// Hard lines longer than Safari shows before the cursor.
    private let lines = (0..<6).map { "P0\($0) กินข้าวกันไหมครับ Keyboards should feel smooth. ผมชอบน้ำใจของคนไทย" }.joined(separator: "\n")

    private func walk(_ host: CuttingHost) -> CursorWalk { CursorWalk(host.shown) }

    /// Measured in Messages: a one-line drag up moved the cursor 79 UTF-16 units back, past the shown sentence.
    func testUpAndDownInAParagraphStayPut() {
        for cut in [CuttingHost.Cut.sentences, .limited(40)] {
            for lines in [-1, 1, -2, 2] {
                var host = CuttingHost(paragraph, cut, cursorAfter: 300)
                var walk = walk(host)
                host.drag(&walk, lines: lines)
                XCTAssertEqual(host.column, 300, "\(cut) \(lines)")
            }
        }
    }

    func testASidewaysDragAcrossWhatTheHostShowsLandsOnEveryCharacter() {
        for cut in [CuttingHost.Cut.sentences, .limited(40)] {
            for lag in [0, 1, 3] {
                var host = CuttingHost(paragraph, cut, cursorAfter: 10, lag: lag)
                var walk = walk(host)
                host.drag(&walk, columns: 3, steps: 50)
                XCTAssertEqual(host.column, 160, "\(cut) lag \(lag)")
                host.drag(&walk, columns: -4, steps: 40)
                XCTAssertEqual(host.column, 0, "\(cut) lag \(lag)")
                XCTAssertFalse(host.splitACharacter, "\(cut) lag \(lag)")
            }
        }
    }

    func testTheEndsOfTheTextHoldTheCursor() {
        let count = paragraph.count
        for cut in [CuttingHost.Cut.sentences, .limited(40)] {
            for lag in [0, 2] {
                var host = CuttingHost(paragraph, cut, cursorAfter: count - 5, lag: lag)
                var walk = walk(host)
                host.drag(&walk, columns: 2, steps: 6)
                XCTAssertEqual(host.column, count, "\(cut) lag \(lag)")
                host.drag(&walk, columns: -1, steps: 3)
                XCTAssertEqual(host.column, count - 3, "\(cut) lag \(lag)")

                var start = CuttingHost(paragraph, cut, cursorAfter: 4, lag: lag)
                walk = self.walk(start)
                start.drag(&walk, columns: -2, steps: 5)
                XCTAssertEqual(start.column, 0, "\(cut) lag \(lag)")
                start.drag(&walk, columns: 1, steps: 2)
                XCTAssertEqual(start.column, 2, "\(cut) lag \(lag)")
            }
        }
    }

    /// The host drops one adjust. The walk must move on from where the host's cursor really is, over Thai without
    /// splitting it.
    func testADroppedAdjustIsCaughtWhenTheHostSettles() {
        for cut in [CuttingHost.Cut.sentences, .limited(40)] {
            var host = CuttingHost(paragraph, cut, cursorAfter: 0)
            host.drops = 1
            var walk = walk(host)
            host.drag(&walk, columns: 1, steps: 3)
            XCTAssertEqual(host.column, 2, "\(cut)")
            host.drag(&walk, columns: 1, steps: 6)
            XCTAssertEqual(host.column, 8, "\(cut)")
            XCTAssertFalse(host.splitACharacter, "\(cut)")
        }
    }

    /// Measured in Safari: an adjust of 3 over น้ำ moved the cursor 4 UTF-16 units, and one of 2 over ดี moved 3.
    /// Safari counts caret stops, so a walk in UTF-16 units runs ahead of the finger on every Thai character with
    /// marks, and can land inside one.
    func testAHostThatCountsCaretStopsMovesOneCharacterAtATime() {
        let text = String(repeating: "น้ำใจ ดีที่ ก่ำ ทำ ", count: 8)
        var host = CuttingHost(text, .limited(40), cursorAfter: 0)
        host.countsCaretStops = true
        var walk = walk(host)
        var landed: [Int?] = []
        for _ in 0..<40 {
            host.drag(&walk, columns: 1)
            landed.append(host.column)
        }
        // Past the first step, which shows how the host counts, each step lands one character on.
        XCTAssertEqual(Array(landed.dropFirst()), (2...40).map { $0 })
        host.drag(&walk, columns: -1, steps: 40)
        XCTAssertEqual(host.column, 0)
        XCTAssertFalse(host.splitACharacter)
    }

    func testUpFromAHardLineLandsOnTheLineAbove() {
        let starts = lines.split(separator: "\n").reduce(into: [0]) { $0.append($0.last! + $1.count + 1) }
        var host = CuttingHost(lines, .sentences, cursorAfter: starts[3] + 10)
        var walk = walk(host)
        host.drag(&walk, lines: -1)
        XCTAssertEqual(host.column, starts[2] + 10)
    }

    /// Safari showed 40 to 68 UTF-16 units before the cursor, less than these lines, so a column can count only from
    /// the start of the shown text. The cursor lands on the right line.
    func testWhereTheHostHidesTheLineStartALineMoveStaysOnTheNextLine() {
        let starts = lines.split(separator: "\n").reduce(into: [0]) { $0.append($0.last! + $1.count + 1) }
        var up = CuttingHost(lines, .limited(40), cursorAfter: starts[3] + 10)
        var walk = walk(up)
        up.drag(&walk, lines: -1)
        XCTAssert((starts[2]..<starts[3]).contains(up.column ?? -1), "up: \(up.column ?? -1)")
        var down = CuttingHost(lines, .limited(40), cursorAfter: starts[2] - 1)
        walk = self.walk(down)
        down.drag(&walk, lines: 1)
        XCTAssert((starts[2]..<starts[3]).contains(down.column ?? -1), "down: \(down.column ?? -1)")
    }

    /// Measured in a UITextView: past the line break the host showed only the new line's first sentence, and the
    /// cursor stopped at its end, 18 characters short of the column.
    func testDownFromTheEndOfALineCrossesTheBreakTheHostHides() {
        let starts = lines.split(separator: "\n").reduce(into: [0]) { $0.append($0.last! + $1.count + 1) }
        var host = CuttingHost(lines, .sentences, cursorAfter: starts[2] - 1)
        var walk = walk(host)
        host.drag(&walk, lines: 1)
        XCTAssertEqual(host.column, starts[3] - 1)
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
