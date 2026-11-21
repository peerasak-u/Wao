import CoreGraphics

/// A key placed on the typing grid.
public struct PlacedKey: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case character(CharacterKey)
        case shift
        case delete
    }

    public let id: String
    public let kind: Kind
    /// Where a touch lands on this key: the cap plus its share of the gaps, out to the screen edge on the outer keys.
    public let hit: CGRect
    public let cap: CGRect

    /// The middle `fraction` of the cap in each direction: a touch here types this key whatever the context says.
    public func anchor(_ fraction: CGFloat) -> CGRect {
        cap.insetBy(dx: cap.width * (1 - fraction) / 2, dy: cap.height * (1 - fraction) / 2)
    }
}

/// Keys are laid out by hand rather than in stacks so the popup and the hit areas know each key's exact frame.
/// It lives here, not in the keyboard, so the tap decoder, its eval and the tests measure the geometry that ships.
public struct KeyLayout: Equatable, Sendable {
    public static let gap = CGSize(width: 5, height: 8)

    public let size: CGSize
    public let keys: [PlacedKey]
    public let rowHeight: CGFloat

    public init(size: CGSize, rows: [[CharacterKey]]) {
        self.size = size
        let columns = CGFloat(max(rows.map(\.count).max() ?? 10, 10))
        let unit = size.width / columns
        let rowHeight = size.height / CGFloat(rows.count + 1)
        self.rowHeight = rowHeight
        var placed: [PlacedKey] = []
        for (r, row) in rows.enumerated() {
            let y = CGFloat(r) * rowHeight
            let isLast = r == rows.count - 1
            let count = CGFloat(row.count)
            let special = isLast ? min(unit * 1.4, (size.width - count * unit) / 2) : 0
            let width = isLast ? (size.width - 2 * special) / count : unit
            let margin = (size.width - 2 * special - count * width) / 2
            func slot(_ x: CGFloat, _ w: CGFloat) -> CGRect {
                CGRect(x: x, y: y, width: w, height: rowHeight).insetBy(dx: Self.gap.width / 2, dy: Self.gap.height / 2)
            }
            if isLast {
                placed.append(.init(id: "shift", kind: .shift, hit: CGRect(x: 0, y: y, width: special, height: rowHeight), cap: slot(0, special)))
            }
            for (c, key) in row.enumerated() {
                let x = special + margin + CGFloat(c) * width
                var hit = CGRect(x: x, y: y, width: width, height: rowHeight)
                if c == 0 { hit = CGRect(x: hit.minX - margin, y: y, width: hit.width + margin, height: rowHeight) }
                if c == row.count - 1 { hit.size.width += margin }
                placed.append(.init(id: "\(r).\(c)", kind: .character(key), hit: hit, cap: slot(x, width)))
            }
            if isLast {
                placed.append(.init(id: "delete", kind: .delete, hit: CGRect(x: size.width - special, y: y, width: special, height: rowHeight), cap: slot(size.width - special, special)))
            }
        }
        keys = placed
    }

    /// The rows of character keys, shift and delete included: everything above the bottom row.
    public var characterArea: CGRect { CGRect(x: 0, y: 0, width: size.width, height: size.height - rowHeight) }

    public var characterKeys: [PlacedKey] {
        keys.filter { if case .character = $0.kind { true } else { false } }
    }

    /// The key whose fixed hit rect holds `point`, shift and delete included.
    public func key(at point: CGPoint) -> PlacedKey? {
        keys.first { $0.hit.contains(point) }
    }
}
