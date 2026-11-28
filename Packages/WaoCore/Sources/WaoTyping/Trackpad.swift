import CoreGraphics
import Foundation

/// The text either side of the cursor, as far as the host shows it. Positions count characters (grapheme clusters),
/// so the cursor never lands between a Thai consonant and the vowel or tone mark sitting on it.
///
/// Where the shown text stops says nothing about lines. In the iOS 26.4 simulator Messages and UITextView stopped at
/// a sentence end, at a line break they did not show, or after 300 UTF-16 units; Safari after about 50 characters.
/// So a line starts or ends only at a line break the text shows.
public struct CursorText: Equatable, Sendable {
    public private(set) var before: String
    public private(set) var after: String

    public init(before: String, after: String) {
        self.before = before
        self.after = after
    }

    /// Moves `count` characters right, or left when negative, stopping at the edge of the known text.
    /// Returns the UTF-16 offset to hand to `adjustTextPosition(byCharacterOffset:)`, 0 when nothing moved.
    public mutating func move(by count: Int) -> Int {
        let characters = self.characters
        let cursor = before.count
        return jump(to: min(max(cursor + count, 0), characters.count), in: characters)
    }

    /// Characters between the start of the cursor's line and the cursor, counted from the start of the known text
    /// when it shows no line break before the cursor.
    public var column: Int {
        let characters = self.characters
        return before.count - lineStart(of: before.count, in: characters)
    }

    /// Moves `lines` lines down, or up when negative, to `column` or the end of a shorter target line.
    /// Only hard line breaks count: a host's soft wrapping is invisible to a keyboard. `nil` when the known text does
    /// not show the line breaks on the way and where the column lands, and nothing moves.
    public mutating func moveLines(by lines: Int, toColumn column: Int? = nil) -> Int? {
        let characters = self.characters
        let cursor = before.count
        var start = lineStart(of: cursor, in: characters)
        let column = column ?? cursor - start
        for _ in 0..<abs(lines) {
            if lines < 0 {
                guard start > 1 else { return nil }
                start = lineStart(of: start - 1, in: characters)
                // The known text may open partway along the line above.
                guard start > 0 else { return nil }
            } else {
                guard let end = lineEnd(of: start, in: characters), end < characters.count else { return nil }
                start = end + 1
            }
        }
        let end = lineEnd(of: start, in: characters)
        let length = (end ?? characters.count) - start
        // Without a line break after it, the target line may go on past the known text.
        guard end != nil || column <= length else { return nil }
        return jump(to: start + min(column, length), in: characters)
    }

    public enum Crossing: Equatable, Sendable {
        /// Stepped over a line break the known text shows; hand over this UTF-16 offset.
        case crossed(Int)
        /// Walked this UTF-16 offset to the edge of the known text, where the host hides what comes next: most likely
        /// a line break, else the end of the text. Only stepping one unit further shows which.
        case edge(Int)
    }

    /// Moves onto the next line down, or up, past the line break that ends or starts the cursor's line. `nil` when
    /// the known text does not show where that is, and nothing moves.
    public mutating func crossLine(down: Bool) -> Crossing? {
        let characters = self.characters
        let cursor = before.count
        if down {
            if let end = lineEnd(of: cursor, in: characters) { return .crossed(jump(to: end + 1, in: characters)) }
            // The hosts measured end what they show after the cursor at a sentence end with the spaces after it, at a
            // line break they hide, at the end of the text, or after 300 UTF-16 units.
            guard after.last.map({ !$0.isWhitespace }) ?? true, after.utf16.count < 300 else { return nil }
            return .edge(jump(to: characters.count, in: characters))
        }
        let start = lineStart(of: cursor, in: characters)
        if start > 0 { return .crossed(jump(to: start - 1, in: characters)) }
        return before.isEmpty ? .edge(0) : nil
    }

    /// Moves along the cursor's line to `column`, or its end when the line is shorter.
    public mutating func moveToColumn(_ column: Int) -> Int {
        let characters = self.characters
        let cursor = before.count
        let start = lineStart(of: cursor, in: characters)
        let end = lineEnd(of: cursor, in: characters) ?? characters.count
        return jump(to: start + min(column, end - start), in: characters)
    }

    /// Takes in what the host shows with its cursor `offset` UTF-16 units from this cursor, where the two agree on
    /// every unit both show and touch or overlap. Returns false, changing nothing, otherwise: the host showed an
    /// older cursor, or other text.
    public mutating func merge(_ shown: CursorText, at offset: Int) -> Bool {
        guard agrees(with: shown, at: offset) else { return false }
        let before = Array(before.utf16), after = Array(after.utf16)
        let known = before + after
        let seen = Array(shown.before.utf16) + Array(shown.after.utf16)
        let from = before.count + offset - shown.before.utf16.count
        let to = from + seen.count
        let head = from < 0 ? seen[..<(-from)] : []
        let tail = to > known.count ? seen[(known.count - from)...] : []
        self.before = String(decoding: head + before, as: UTF16.self)
        self.after = String(decoding: after + tail, as: UTF16.self)
        return true
    }

    /// Whether what the host shows, with its cursor `offset` UTF-16 units from this cursor, matches every unit both
    /// show and touches or overlaps this text.
    public func agrees(with shown: CursorText, at offset: Int) -> Bool {
        let before = Array(before.utf16)
        let known = before + Array(after.utf16)
        let seen = Array(shown.before.utf16) + Array(shown.after.utf16)
        let from = before.count + offset - shown.before.utf16.count
        let to = from + seen.count
        guard from <= known.count, to >= 0 else { return false }
        return (max(from, 0)..<min(to, known.count)).allSatisfy { known[$0] == seen[$0 - from] }
    }

    /// The caret stops in the `units` UTF-16 units the cursor just crossed, signed like `units`. Safari stops at each
    /// character, and again before a SARA AM that follows other marks: น้ำ is two stops, น้ and ำ.
    func caretStops(over units: Int) -> Int {
        let known = Array(before.utf16) + Array(after.utf16)
        let cursor = before.utf16.count
        let range = units > 0 ? max(cursor - units, 0)..<cursor : cursor..<min(cursor - units, known.count)
        let crossed = String(decoding: known[range], as: UTF16.self)
        let stops = crossed.reduce(0) { stops, character in
            stops + 1 + character.unicodeScalars.dropFirst().filter { $0 == "\u{0E33}" || $0 == "\u{0EB3}" }.count
        }
        return units.signum() * stops
    }

    /// Moves the cursor `units` UTF-16 units, where the host put it.
    mutating func shift(by units: Int) {
        let known = Array(before.utf16) + Array(after.utf16)
        let cursor = min(max(before.utf16.count + units, 0), known.count)
        before = String(decoding: known[..<cursor], as: UTF16.self)
        after = String(decoding: known[cursor...], as: UTF16.self)
    }

    /// The two sides are kept apart so a mark the host left right after the cursor cannot merge into the
    /// character before it.
    private var characters: [Character] { Array(before) + Array(after) }

    private mutating func jump(to target: Int, in characters: [Character]) -> Int {
        let cursor = before.count
        let offset = target >= cursor
            ? characters[cursor..<target].reduce(0) { $0 + $1.utf16.count }
            : -characters[target..<cursor].reduce(0) { $0 + $1.utf16.count }
        before = String(characters[..<target])
        after = String(characters[target...])
        return offset
    }

    private func lineStart(of index: Int, in characters: [Character]) -> Int {
        var i = index
        while i > 0, !characters[i - 1].isNewline { i -= 1 }
        return i
    }

    /// The index of the line break ending the line that holds `index`, or `nil` when the known text ends first.
    private func lineEnd(of index: Int, in characters: [Character]) -> Int? {
        characters[index...].firstIndex(where: \.isNewline)
    }
}

/// The space key: a tap types a space; a hold turns the whole keyboard into a trackpad for the cursor.
public struct SpaceTrackpad: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Finger down on space, waiting out `holdDelay`.
        case pressed(at: CGPoint)
        case tracking(Drag)
        /// A second finger or a slide off the key settled this touch; nothing more until every finger lifts.
        case ended
    }

    /// The finger's motion while it moves the cursor.
    public struct Drag: Equatable, Sendable {
        var point: CGPoint
        var time: TimeInterval?
        /// Smoothed, in pt/s.
        var velocity = CGVector.zero
        /// Where the hold began, so the cursor's column follows the finger's position and a drag back lands where
        /// it started.
        var startX: CGFloat
        /// Columns already handed out.
        var columns = 0
        /// Vertical travel toward the next line move.
        var rise: CGFloat = 0
        /// A line moved in this vertical run, so the next one takes only `lineStep`.
        var climbing = false
    }

    public enum Effect: Equatable, Sendable {
        case space
        case begin
        case move(columns: Int, lines: Int)
        case end
    }

    /// The system keyboard's, measured from a recording of a held space in the iOS 26.4 simulator.
    public static let holdDelay: TimeInterval = 0.65
    /// About one character of 17 pt text, at any speed, so the cursor stays under the finger as the system
    /// keyboard's does. Speed-scaled gain made a normal drag skip two or three characters a frame, which read as
    /// jumping by words.
    public static let pointsPerCharacter: CGFloat = 9
    /// Vertical travel that starts a run of line moves, and then moves each further line: about one line of 17 pt text.
    /// The first is larger so a drag has to mean it.
    public static let lineThreshold: CGFloat = 30
    public static let lineStep: CGFloat = 22
    /// While the finger moves at least this many times faster sideways than up or down, vertical travel is drift.
    static let horizontalDominance: CGFloat = 2
    static let smoothing: TimeInterval = 0.04

    public private(set) var phase: Phase = .idle

    public init() {}

    /// A finger landed on the key. A second one while the first is down settles the first.
    public mutating func down(at point: CGPoint) -> Effect? {
        switch phase {
        case .idle:
            phase = .pressed(at: point)
            return nil
        case .pressed:
            phase = .ended
            return .space
        case .tracking:
            phase = .ended
            return .end
        case .ended:
            return nil
        }
    }

    /// `holdDelay` passed with the finger still on the key.
    public mutating func held() -> Effect? {
        guard case .pressed(let point) = phase else { return nil }
        phase = .tracking(Drag(point: point, startX: point.x))
        return .begin
    }

    /// The finger is at `point` at `time`, a touch timestamp. Before the hold, `onKey` says whether the finger is
    /// still on space; sliding off abandons the space.
    public mutating func moved(to point: CGPoint, at time: TimeInterval, onKey: Bool) -> Effect? {
        switch phase {
        case .pressed:
            phase = onKey ? .pressed(at: point) : .ended
            return nil
        case .tracking(var drag):
            let (columns, lines) = Self.track(&drag, to: point, at: time)
            phase = .tracking(drag)
            guard columns != 0 || lines != 0 else { return nil }
            return .move(columns: columns, lines: lines)
        case .idle, .ended:
            return nil
        }
    }

    private static func track(_ drag: inout Drag, to point: CGPoint, at time: TimeInterval) -> (columns: Int, lines: Int) {
        let dx = point.x - drag.point.x
        let dy = point.y - drag.point.y
        if let last = drag.time, time > last {
            let dt = time - last
            let k = CGFloat(1 - exp(-dt / smoothing))
            drag.velocity.dx += k * (dx / CGFloat(dt) - drag.velocity.dx)
            drag.velocity.dy += k * (dy / CGFloat(dt) - drag.velocity.dy)
        }
        drag.point = point
        drag.time = time

        let columns = Int((point.x - drag.startX) / pointsPerCharacter) - drag.columns
        drag.columns += columns

        var lines = 0
        if abs(drag.velocity.dx) > horizontalDominance * abs(drag.velocity.dy) {
            drag.rise = 0
            drag.climbing = false
        } else {
            drag.rise += dy
            while abs(drag.rise) >= (drag.climbing ? lineStep : lineThreshold) {
                let step: CGFloat = drag.rise > 0 ? 1 : -1
                drag.rise -= step * (drag.climbing ? lineStep : lineThreshold)
                drag.climbing = true
                lines += Int(step)
            }
        }
        return (columns, lines)
    }

    /// The last finger lifted.
    public mutating func lifted() -> Effect? {
        defer { phase = .idle }
        switch phase {
        case .pressed: return .space
        case .tracking: return .end
        case .idle, .ended: return nil
        }
    }

    /// A finger elsewhere on the keyboard ended trackpad mode while this one is still down.
    public mutating func interrupted() -> Effect? {
        guard case .tracking = phase else { return nil }
        phase = .ended
        return .end
    }

    /// The system took the touch.
    public mutating func cancelled() -> Effect? {
        defer { phase = .idle }
        if case .tracking = phase { return .end }
        return nil
    }
}
