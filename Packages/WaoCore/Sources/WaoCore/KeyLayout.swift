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

    public var slot: KeySlot { KeySlot(hit: hit, cap: cap) }

    /// The middle `fraction` of the cap in each direction: a touch here types this key whatever the context says.
    public func anchor(_ fraction: CGFloat) -> CGRect {
        cap.insetBy(dx: cap.width * (1 - fraction) / 2, dy: cap.height * (1 - fraction) / 2)
    }
}

/// A bottom-row key: no character, so only where it is drawn and where it takes touches.
public struct KeySlot: Equatable, Sendable {
    public let hit: CGRect
    public let cap: CGRect
}

/// The iPhone system keyboard's measurements (iOS 26, portrait), read off screenshots with tools/keyboard_parity.py.
public struct KeyMetrics: Equatable, Sendable {
    /// Screen edge to the outermost caps.
    public let margin: CGFloat
    /// Height of the band the rows share, bottom row included, whatever the number of rows.
    public let rowsHeight: CGFloat
    /// Between two caps in a row.
    public let gap: CGFloat = 6
    /// Top of the keyboard to the top of the first row's caps; the suggestion strip lives above.
    public let firstCapTop: CGFloat = 35

    /// Measured at 390 pt (iPhone 16e) and 440 pt (iPhone 17 Pro Max); a Pro Max class width gets the second.
    public init(width: CGFloat) {
        if width >= 428 {
            margin = 20.0 / 3
            rowsHeight = 224
        } else {
            margin = 26.0 / 3
            rowsHeight = 216
        }
    }

    /// Gap between two rows of caps: tighter when the Thai page fits five rows into the same band.
    public func rowGap(rows: Int) -> CGFloat { rows >= 5 ? 6 : 11 }

    /// A cap plus the gap after it, when `columns` caps fill the width between the margins.
    public func pitch(columns: Int, width: CGFloat) -> CGFloat { (width - 2 * margin + gap) / CGFloat(columns) }

    /// The keyboard's height, suggestion strip included: the bottom of the five-row page's lowest caps.
    public var height: CGFloat { firstCapTop + rowsHeight - rowGap(rows: 5) }
}

/// Keys are laid out by hand rather than in stacks so the popup and the hit areas know each key's exact frame.
/// It lives here, not in the keyboard, so the tap decoder, its eval and the tests measure the geometry that ships.
/// Coordinates start at the top of the key area, below the suggestion strip.
public struct KeyLayout: Equatable, Sendable {
    /// Above the key area: suggestions, or the Full Access banner.
    public static func stripHeight(width: CGFloat) -> CGFloat {
        let metrics = KeyMetrics(width: width)
        return metrics.firstCapTop - metrics.rowGap(rows: 5) / 2
    }

    public let size: CGSize
    public let keys: [PlacedKey]
    public let metrics: KeyMetrics
    /// Screen edge to the edge of our view.
    private let inset: CGFloat
    private let bottomCap: CGRect
    private let bottomHitTop: CGFloat

    /// `rows` are the character rows. Shift and delete flank the last one, and the bottom row (page, language, space,
    /// return) comes from `bottomRow(leading:)`. iOS 26 gives a third-party keyboard a view narrower than the screen,
    /// centred on it, while the system keyboard spreads its caps over the whole `screenWidth`; the caps go where the
    /// system draws them and the hit areas stop at the edges of our `width`.
    public init(width: CGFloat, screenWidth: CGFloat? = nil, rows: [[CharacterKey]]) {
        let screen = max(screenWidth ?? width, width)
        let metrics = KeyMetrics(width: screen)
        let strip = Self.stripHeight(width: screen)
        self.metrics = metrics
        size = CGSize(width: width, height: metrics.height - strip)
        let inset = (screen - width) / 2, viewWidth = width
        self.inset = inset
        let width = screen
        let m = metrics.margin, g = metrics.gap
        let last = rows.count - 1
        let columns = max(rows.map(\.count).max() ?? 10, (rows.last?.count ?? 0) + 2, 10)
        let pitch = metrics.pitch(columns: columns, width: width)
        let capWidth = pitch - g
        let rowPitch = metrics.rowsHeight / CGFloat(rows.count + 1)
        let capHeight = rowPitch - metrics.rowGap(rows: rows.count + 1)
        func capTop(_ r: Int) -> CGFloat { metrics.firstCapTop - strip + CGFloat(r) * rowPitch }
        /// Halfway between one row's caps and the next, the edge of the view above the first.
        func hitTop(_ r: Int) -> CGFloat { r == 0 ? 0 : (capTop(r - 1) + capHeight + capTop(r)) / 2 }

        var placed: [PlacedKey] = []
        for (r, row) in rows.enumerated() {
            var caps: [CGRect]
            if r == last, row.count + 2 == columns {
                caps = (0..<columns).map { CGRect(x: m + CGFloat($0) * pitch, y: capTop(r), width: capWidth, height: capHeight) }
            } else if r == last {
                // Letters share the span between one and a half columns in from each side; shift and delete take the rest.
                let span = width - 2 * (m + 1.5 * pitch)
                let w = (span - CGFloat(row.count - 1) * g) / CGFloat(row.count)
                let special = capWidth * 1.345
                caps = [CGRect(x: m, y: capTop(r), width: special, height: capHeight)]
                caps += row.indices.map { CGRect(x: m + 1.5 * pitch + CGFloat($0) * (w + g), y: capTop(r), width: w, height: capHeight) }
                caps.append(CGRect(x: width - m - special, y: capTop(r), width: special, height: capHeight))
            } else {
                let indent = CGFloat(columns - row.count) / 2 * pitch
                caps = row.indices.map { CGRect(x: m + indent + CGFloat($0) * pitch, y: capTop(r), width: capWidth, height: capHeight) }
            }
            let top = hitTop(r), bottom = hitTop(r + 1)
            let hits = Self.hits(caps, inset: inset, width: viewWidth, top: top, bottom: bottom)
            caps = caps.map { $0.offsetBy(dx: -inset, dy: 0) }
            var kinds: [(String, PlacedKey.Kind)] = row.enumerated().map { ("\(r).\($0.offset)", .character($0.element)) }
            if r == last { kinds = [("shift", .shift)] + kinds + [("delete", .delete)] }
            placed += zip(kinds, zip(hits, caps)).map { PlacedKey(id: $0.0, kind: $0.1, hit: $1.0, cap: $1.1) }
        }
        keys = placed
        bottomCap = CGRect(x: m, y: capTop(rows.count), width: width - 2 * m, height: capHeight)
        bottomHitTop = hitTop(rows.count)
    }

    /// Each cap's hit area runs to the middle of the gaps beside it, and the outer ones to the edges of our view,
    /// `width` wide and `inset` in from the screen's edge. Takes screen coordinates, returns view coordinates.
    private static func hits(_ caps: [CGRect], inset: CGFloat, width: CGFloat, top: CGFloat, bottom: CGFloat) -> [CGRect] {
        caps.indices.map { i in
            let left = i == 0 ? 0 : (caps[i - 1].maxX + caps[i].minX) / 2 - inset
            let right = i == caps.count - 1 ? width : (caps[i].maxX + caps[i + 1].minX) / 2 - inset
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
    }

    /// The bottom row: `leading` small keys, then space, then return. The system keyboard has two leading keys
    /// (123 and emoji) and lines space and return up with the second row's third and eighth keys; each extra
    /// leading key, the size of the others, comes out of the space bar.
    public func bottomRow(leading: Int) -> (leading: [KeySlot], space: KeySlot, enter: KeySlot) {
        let screen = size.width + 2 * inset
        let m = metrics.margin, g = metrics.gap, y = bottomCap.minY, h = bottomCap.height
        let pitch = metrics.pitch(columns: 10, width: screen)
        let returnX = m + 7.5 * pitch
        let small = (m + 2.5 * pitch - g - m - g) / 2
        var caps = (0..<leading).map { CGRect(x: m + CGFloat($0) * (small + g), y: y, width: small, height: h) }
        let spaceX = m + CGFloat(leading) * (small + g)
        caps.append(CGRect(x: spaceX, y: y, width: returnX - g - spaceX, height: h))
        caps.append(CGRect(x: returnX, y: y, width: screen - m - returnX, height: h))
        let hits = Self.hits(caps, inset: inset, width: size.width, top: bottomHitTop, bottom: size.height)
        let slots = zip(hits, caps.map { $0.offsetBy(dx: -inset, dy: 0) }).map(KeySlot.init)
        return (Array(slots.prefix(leading)), slots[leading], slots[leading + 1])
    }

    /// The rows of character keys, shift and delete included: everything above the bottom row.
    public var characterArea: CGRect { CGRect(x: 0, y: 0, width: size.width, height: bottomHitTop) }

    public var characterKeys: [PlacedKey] {
        keys.filter { if case .character = $0.kind { true } else { false } }
    }

    /// The key whose fixed hit rect holds `point`, shift and delete included.
    public func key(at point: CGPoint) -> PlacedKey? {
        keys.first { $0.hit.contains(point) }
    }
}
