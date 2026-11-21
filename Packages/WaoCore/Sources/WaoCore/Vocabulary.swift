import Foundation

/// `tokens.txt`: a piece per line, id = line number - 1. The blank is the id after the last piece.
public struct Vocabulary: Sendable {
    public let pieces: [String]

    public var blankID: Int { pieces.count }

    public init(pieces: [String]) {
        self.pieces = pieces
    }

    public init(contentsOf url: URL) throws {
        var lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        self.init(pieces: lines)
    }

    /// Joins pieces, drops control pieces such as `<th-TH>` and `<unk>`, and turns `▁` into spaces.
    public func text(for ids: [Int]) -> String {
        ids.map { pieces[$0] }
            .filter { !($0.hasPrefix("<") && $0.hasSuffix(">")) }
            .joined()
            .replacingOccurrences(of: "\u{2581}", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
