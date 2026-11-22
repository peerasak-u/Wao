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

    /// Moves `lines` lines down, or up when negative, keeping the column where the target line is long enough.
    /// Only hard line breaks count: a host's soft wrapping is invisible to a keyboard. `nil` when the target line
    /// is not in the known text, so the cursor stays put rather than jumping somewhere unexpected.
    public mutating func moveLines(by lines: Int) -> Int? {
        let characters = self.characters
        let cursor = before.count
        let start = lineStart(of: cursor, in: characters)
        let column = cursor - start
        var target = start
        for _ in 0..<abs(lines) {
            if lines < 0 {
                guard target > 0 else { return nil }
                target = lineStart(of: target - 1, in: characters)
            } else {
                guard let end = lineEnd(of: target, in: characters), end < characters.count else { return nil }
                target = end + 1
            }
        }
        let length = (lineEnd(of: target, in: characters) ?? characters.count) - target
        return jump(to: target + min(column, length), in: characters)
    }

    /// Moves to the end of the line, or its start, as far as the known text shows it.
    public mutating func moveToLineEdge(down: Bool) -> Int {
        let characters = self.characters
        let cursor = before.count
        let target = down ? lineEnd(of: cursor, in: characters) ?? characters.count : lineStart(of: cursor, in: characters)
        return jump(to: target, in: characters)
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
        /// The finger's movement since `anchor` has not yet added up to a whole step.
        case tracking(anchor: CGPoint)
        /// A second finger or a slide off the key settled this touch; nothing more until every finger lifts.
        case ended
    }

    public enum Effect: Equatable, Sendable {
        case space
        case begin
        case move(columns: Int, lines: Int)
        case end
    }

    /// The system keyboard's, measured from a recording of a held space in the iOS 26.4 simulator.
    public static let holdDelay: TimeInterval = 0.65
    /// Finger travel per character and per line: about one character and one line of 17 pt text.
    public static let step = CGSize(width: 9, height: 22)

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
        phase = .tracking(anchor: point)
        return .begin
    }

    /// Before the hold, `onKey` says whether the finger is still on space; sliding off abandons the space.
    public mutating func moved(to point: CGPoint, onKey: Bool) -> Effect? {
        switch phase {
        case .pressed:
            if onKey {
                phase = .pressed(at: point)
            } else {
                phase = .ended
            }
            return nil
        case .tracking(let anchor):
            let columns = Int((point.x - anchor.x) / Self.step.width)
            let lines = Int((point.y - anchor.y) / Self.step.height)
            guard columns != 0 || lines != 0 else { return nil }
            phase = .tracking(anchor: CGPoint(x: anchor.x + CGFloat(columns) * Self.step.width,
                                              y: anchor.y + CGFloat(lines) * Self.step.height))
            return .move(columns: columns, lines: lines)
        case .idle, .ended:
            return nil
        }
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
