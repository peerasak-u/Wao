/// Walks the host's cursor for the space-bar trackpad, through its own copy of the text so a move never waits on
/// the host. The host shows only part of the text, and its reports trail the adjusts: in the iOS 26.4 simulator
/// Safari reported each adjust twice, first with the cursor where it was. So a report is taken in only where it
/// agrees with the copy at a place the walk put the cursor, and the walk asks for more only past the copy's edge.
/// Hosts do not always go where they are told. UIKit hosts move the cursor by UTF-16 units; Safari moves it by caret
/// stops, so an adjust of 2 over ดี went on past the next character. A report that agrees with the copy somewhere
/// the walk never put the cursor shows where the host went: the walk follows, and from a host that went further than
/// told it learns to count caret stops. A report once the host has settled is the truth, and the copy is replaced
/// when it disagrees.
public struct CursorWalk: Equatable, Sendable {
    private enum Wait: Equatable, Sendable {
        /// Past the edge of the copy, until a report shows more.
        case text
        /// Moved `step`, one UTF-16 unit, past where the host shows nothing: a line break it hides, or the end of the
        /// text. For a line move `back` is the UTF-16 offset to the cursor before the line move, in case it was not
        /// a line break.
        case probe(step: Int, back: Int?)
        /// Crossed a line break, to be walked to the goal column once a report shows the new line.
        case line
    }

    private var text: CursorText
    /// The host's cursor once it applies every adjust, in UTF-16 units from where tracking began.
    private var position = 0
    /// Places the adjusts took the host's cursor that no report has shown yet, oldest first.
    private var unread: [Int] = []
    /// The last places reports showed the host's cursor, newest last. Safari repeats the last one after each adjust.
    private var confirmed = [0]
    private var columns = 0
    private var lines = 0
    private var wait: Wait?
    /// The column line moves aim for, kept across a shorter line as the finger's position is, until a move sideways.
    private var goal: Int?
    /// The text ends at the cursor this way: the host ignored a step past it.
    private var end: Int?
    /// The host counts adjusts in caret stops, as Safari did, not UTF-16 units.
    private var countsCaretStops = false
    /// The last move handed to the host, in UTF-16 units.
    private var last = 0

    /// A move of the copy's cursor, and what it takes to move the host's cursor there.
    private struct Move {
        var units = 0
        var command = 0

        mutating func add(_ other: Self) {
            units += other.units
            command += other.command
        }
    }

    public init(_ text: CursorText) {
        self.text = text
    }

    /// The finger moved. Returns the offset for `adjustTextPosition(byCharacterOffset:)`, 0 for none.
    public mutating func move(columns: Int, lines: Int) -> Int {
        self.columns += columns
        self.lines += lines
        return walk()
    }

    /// The host reported its text, as it does after each adjust.
    public mutating func read(_ shown: CursorText) -> Int {
        guard take(shown) else { return 0 }
        return resume()
    }

    /// The host had time to apply every adjust, so what it shows is where its cursor is.
    public mutating func settle(_ shown: CursorText) -> Int {
        if take(shown), unread.isEmpty { return resume() }
        unread = []
        if case .probe(let step, let back) = wait, take(shown, at: position - step) {
            // The host ignored the step: the text ends here.
            position -= step
            wait = nil
            guard let back else {
                end = step
                if columns.signum() == step { columns = 0 }
                return walk()
            }
            lines = 0
            text.shift(by: back)
            return record(measure(back)) + walk()
        }
        // The host's cursor is not where the walk put it: it clamped or dropped an adjust. Carry on from there.
        text = shown
        if wait == .line { return finishLine() }
        wait = nil
        return walk()
    }

    /// Merges a report at the newest unread place it agrees with, or follows the host to where it went instead.
    private mutating func take(_ shown: CursorText) -> Bool {
        for i in unread.indices.reversed() where take(shown, at: unread[i]) {
            confirm(unread[i])
            unread.removeSubrange(...i)
            return true
        }
        if unread.isEmpty, take(shown, at: position) {
            confirm(position)
            return true
        }
        return follow(shown)
    }

    /// With at most one adjust unreported, a report can only show a place already confirmed, that adjust's place, or
    /// where the host went instead. Nearby, and only one place, so repeated text cannot mislead it.
    private mutating func follow(_ shown: CursorText) -> Bool {
        if case .probe = wait { return false }
        guard unread.count <= 1 else { return false }
        let reach = min(64, max(8, 3 * abs(last)))
        let places = (-reach...reach).map { position + $0 }.filter { text.agrees(with: shown, at: $0 - position) }
        guard places.count == 1, let place = places.first, place != position, !confirmed.contains(place) else {
            return false
        }
        if (place - position).signum() == last.signum() { countsCaretStops = true }
        _ = text.merge(shown, at: place - position)
        let start = text.before.count
        text.shift(by: place - position)
        // The finger has not moved: walk back the characters the host went past it, or on to the ones it fell short.
        columns -= text.before.count - start
        position = place
        confirm(place)
        unread = []
        return true
    }

    private mutating func confirm(_ place: Int) {
        confirmed.append(place)
        if confirmed.count > 4 { confirmed.removeFirst() }
    }

    /// A probe leaves the copy's cursor one unit short of `position`.
    private mutating func take(_ shown: CursorText, at place: Int) -> Bool {
        var probed = 0
        if case .probe(let step, _) = wait { probed = step }
        return text.merge(shown, at: place - (position - probed))
    }

    private mutating func resume() -> Int {
        guard unread.isEmpty else { return wait == .text ? continueWalk() : 0 }
        switch wait {
        case .probe(let step, let back):
            wait = nil
            text.shift(by: step)
            let crossed = step > 0 ? text.before.last : text.after.first
            if let back, crossed?.isNewline != true {
                lines = 0
                text.shift(by: back - step)
                return record(measure(back - step)) + walk()
            }
            if back != nil { return finishLine() }
            return walk()
        case .line:
            return finishLine()
        case .text, nil:
            return continueWalk()
        }
    }

    private mutating func continueWalk() -> Int {
        if wait == .text { wait = nil }
        return walk()
    }

    /// Walks the new line to the goal column. The end of the shown text is no line end: short of the goal there, the
    /// walk goes to it and waits to be shown more.
    private mutating func finishLine() -> Int {
        let goal = goal ?? 0
        let units = text.moveToColumn(goal)
        if units != 0, text.after.isEmpty, text.column < goal {
            wait = .line
            return record(measure(units))
        }
        wait = nil
        return record(measure(units)) + walk()
    }

    private mutating func walk() -> Int {
        guard wait == nil else { return 0 }
        var moved = Move()
        while lines != 0, wait == nil {
            let step = lines.signum()
            // Where the host hides the line's start, the column counts from the start of the shown text: exact at the
            // start of the text, short of the finger in a long line, and on the right line either way.
            let column = goal ?? text.column
            goal = column
            if let units = text.moveLines(by: step, toColumn: column) {
                moved.add(measure(units))
                lines -= step
                continue
            }
            var copy = text
            switch copy.crossLine(down: step > 0) {
            case .crossed(let units):
                text = copy
                moved.add(measure(units))
                lines -= step
                wait = .line
            case .edge(let units):
                guard unread.isEmpty, moved.units == 0 else { return record(moved) + waitForText() }
                text = copy
                moved.add(measure(units))
                moved.add(Move(units: step, command: step))
                lines -= step
                wait = .probe(step: step, back: -units)
            case nil:
                // The host may show the line break once it catches up; if it does not, moving would be a guess.
                guard unread.isEmpty, moved.units == 0 else { return record(moved) + waitForText() }
                lines = 0
            }
        }
        if wait == nil, columns != 0 {
            goal = nil
            let start = text.before.count
            let units = text.move(by: columns)
            moved.add(measure(units))
            columns -= text.before.count - start
            if columns != 0 {
                let step = columns.signum()
                if !unread.isEmpty || moved.units != 0 {
                    wait = .text
                } else if end == step {
                    columns = 0
                } else {
                    moved.add(Move(units: step, command: step))
                    columns -= step
                    wait = .probe(step: step, back: nil)
                }
            }
        }
        return record(moved)
    }

    private mutating func waitForText() -> Int {
        wait = .text
        return 0
    }

    /// The copy's cursor just moved `units`. Call it once the copy has moved, not in the same expression.
    private func measure(_ units: Int) -> Move {
        Move(units: units, command: countsCaretStops ? text.caretStops(over: units) : units)
    }

    private mutating func record(_ move: Move) -> Int {
        guard move.units != 0 else { return 0 }
        position += move.units
        last = move.units
        unread.append(position)
        if unread.count > 32 { unread.removeFirst() }
        end = nil
        return move.command
    }
}
