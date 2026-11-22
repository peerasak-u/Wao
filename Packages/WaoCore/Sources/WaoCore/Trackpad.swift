import CoreGraphics
import Foundation

/// The text either side of the cursor, as far as the host shows it. Positions count characters (grapheme clusters),
/// so the cursor never lands between a Thai consonant and the vowel or tone mark sitting on it.
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

    /// Characters between the start of the cursor's line and the cursor.
    public var column: Int {
        let characters = self.characters
        return before.count - lineStart(of: before.count, in: characters)
    }

    /// Moves `lines` lines down, or up when negative, to `column` or the end of a shorter target line.
    /// Only hard line breaks count: a host's soft wrapping is invisible to a keyboard. `nil` when the known text does
    /// not show where that column is, and nothing moves; `crossLine` then gets there through the host.
    public mutating func moveLines(by lines: Int, toColumn column: Int? = nil) -> Int? {
        let characters = self.characters
        let cursor = before.count
        var start = lineStart(of: cursor, in: characters)
        let column = column ?? cursor - start
        for _ in 0..<abs(lines) {
            if lines < 0 {
                // At 1 the known text opens on the line break above the cursor's line, and the line before it is hidden.
                guard start > 1 else { return nil }
                start = lineStart(of: start - 1, in: characters)
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

    /// Moves past the known text onto the next line down, or up, through the line break the host hides, and returns
    /// that UTF-16 offset. Once the host shows the new line, `moveToColumn` finishes the move. At either end of the
    /// text there is no line to reach, and the column puts the cursor back where it was. `nil` when the host shows
    /// no text at all, so the column is unknown.
    public mutating func crossLine(down: Bool) -> Int? {
        let characters = self.characters
        guard !characters.isEmpty else { return nil }
        let cursor = before.count
        let start = lineStart(of: cursor, in: characters)
        if down {
            if let end = lineEnd(of: cursor, in: characters) { return jump(to: end + 1, in: characters) }
            return jump(to: characters.count, in: characters) + 1
        }
        return start > 0 ? jump(to: start - 1, in: characters) : jump(to: 0, in: characters) - 1
    }

    /// Moves along the cursor's line to `column`, or its end when the line is shorter.
    public mutating func moveToColumn(_ column: Int) -> Int {
        let characters = self.characters
        let cursor = before.count
        let start = lineStart(of: cursor, in: characters)
        let end = lineEnd(of: cursor, in: characters) ?? characters.count
        return jump(to: start + min(column, end - start), in: characters)
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

    /// The finger's motion while it moves the cursor, and the parts of it too small to move the cursor yet.
    public struct Drag: Equatable, Sendable {
        var point: CGPoint
        var time: TimeInterval?
        /// Smoothed, in pt/s.
        var velocity = CGVector.zero
        /// Characters moved by the finger but not yet by the cursor, so no motion is lost to rounding.
        var columns: CGFloat = 0
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
    /// About one character of 17 pt text, below `precisionSpeed`.
    public static let pointsPerCharacter: CGFloat = 9
    /// Pointer acceleration in the shape of libinput's adaptive profile: one to one below `precisionSpeed` (pt/s),
    /// then each `accelerationSpan` faster adds one more, up to `maxGain`. A slow 380 pt drag across the keyboard
    /// moves about 53 characters, and a 150 pt flick in 0.15 s about 45.
    static let precisionSpeed: CGFloat = 60
    static let accelerationSpan: CGFloat = 240
    static let maxGain: CGFloat = 3
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
        phase = .tracking(Drag(point: point))
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

        let gain = min(maxGain, 1 + max(0, abs(drag.velocity.dx) - precisionSpeed) / accelerationSpan)
        drag.columns += dx / pointsPerCharacter * gain
        let columns = Int(drag.columns)
        drag.columns -= CGFloat(columns)

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
