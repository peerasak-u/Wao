/// Walks the host's cursor for the space-bar trackpad. In the simulator the host's own view of the text lagged a
/// move by up to 25 ms and often showed only the cursor's line, so the walk moves through its own copy and asks the
/// host again only past the copy's edge. Moves that arrive while it waits are kept, not dropped.
public struct CursorWalk: Equatable, Sendable {
    public enum Command: Equatable, Sendable {
        /// Hand to `adjustTextPosition(byCharacterOffset:)`.
        case adjust(Int)
        /// Read the host's text once it has caught up, and pass it to `read(_:)`.
        case read
    }

    private enum Wait: Equatable, Sendable {
        /// The copy ran out; the host may show more now.
        case edge
        /// Stepped over a line break the host hides, from what the host showed then.
        case lineBreak(from: CursorText)
        /// Crossed onto a line the host hid, to be walked to the goal column once it shows.
        case line
    }

    private var text: CursorText
    private var columns = 0
    private var lines = 0
    private var wait: Wait?
    /// The column line moves aim for, kept across a shorter line as the finger's position is, until a move sideways.
    private var goal: Int?

    public init(_ text: CursorText) {
        self.text = text
    }

    public mutating func move(columns: Int, lines: Int) -> [Command] {
        self.columns += columns
        self.lines += lines
        var commands: [Command] = []
        if wait == nil { walk(&commands) }
        return commands
    }

    /// What the host shows after a `.read`.
    public mutating func read(_ shown: CursorText) -> [Command] {
        guard let wait else { return [] }
        self.wait = nil
        text = shown
        var commands: [Command] = []
        switch wait {
        case .edge:
            walk(&commands, askedAtEdge: true)
        case .lineBreak(let before):
            // Nothing moved: this is the end of the text, not a line break.
            if shown == before { columns = 0 }
            walk(&commands)
        case .line:
            Self.add(text.moveToColumn(goal ?? 0), to: &commands)
            walk(&commands)
        }
        return commands
    }

    private mutating func walk(_ commands: inout [Command], askedAtEdge: Bool = false) {
        while lines != 0 {
            let step = lines.signum()
            lines -= step
            let column = goal ?? text.column
            if let offset = text.moveLines(by: step, toColumn: column) {
                goal = column
                Self.add(offset, to: &commands)
            } else if let offset = text.crossLine(down: step > 0) {
                goal = column
                Self.add(offset, to: &commands)
                wait = .line
                commands.append(.read)
                return
            }
        }
        guard columns != 0 else { return }
        goal = nil
        let start = text.before.count
        Self.add(text.move(by: columns), to: &commands)
        let moved = text.before.count - start
        columns -= moved
        guard columns != 0 else { return }
        if askedAtEdge, moved == 0 {
            // The host still shows nothing this way: a line break it hides, one UTF-16 unit, or the end of the text.
            let step = columns.signum()
            columns -= step
            Self.add(step, to: &commands)
            wait = .lineBreak(from: text)
        } else {
            wait = .edge
        }
        commands.append(.read)
    }

    private static func add(_ offset: Int, to commands: inout [Command]) {
        guard offset != 0 else { return }
        if case .adjust(let previous) = commands.last {
            commands[commands.count - 1] = .adjust(previous + offset)
        } else {
            commands.append(.adjust(offset))
        }
    }
}
