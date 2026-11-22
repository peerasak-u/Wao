import Foundation

/// A character key: what it types unshifted and shifted.
public struct CharacterKey: Equatable, Hashable, Sendable {
    public let output: String
    public let shifted: String

    public func text(shifted isShifted: Bool) -> String { isShifted ? shifted : output }
}

/// The typing keyboard's state: whether the numbers page is up, and shift. It only exists so the keyboard still types
/// without Full Access (App Review 4.4.1). The letters are Thai only; English comes from dictation or the system's
/// own keyboard through the globe.
public struct Typing: Equatable, Sendable {
    public enum Page: Sendable { case letters, numbers }

    public private(set) var page: Page = .letters
    public private(set) var shifted = false

    public init() {}

    public var rows: [[CharacterKey]] {
        switch page {
        case .letters: Self.kedmanee
        case .numbers: Self.numbers
        }
    }

    /// Only the letters page reads taps through the language model; the symbols stay geometric.
    public var decodes: Bool { page == .letters }

    /// Caption of the key that flips between letters and the numbers page.
    public var pageLabel: String { page == .letters ? "123" : "กขค" }

    /// On the numbers page shift is the way to the second symbols page, so it reads as such.
    public var shiftLabel: String? {
        guard page == .numbers else { return nil }
        return shifted ? "123" : "#+="
    }

    /// Shift on letters lasts one character, like the system keyboard; on the numbers page it stays put.
    public mutating func type(_ key: CharacterKey) -> String {
        let text = key.text(shifted: shifted)
        if page == .letters { shifted = false }
        return text
    }

    public mutating func toggleShift() { shifted.toggle() }

    public mutating func togglePage() {
        page = page == .letters ? .numbers : .letters
        shifted = false
    }

    /// Splits on scalars because a Thai combining mark after a space joins the space's grapheme cluster.
    private static func row(_ plain: String, _ shifted: String) -> [CharacterKey] {
        func keys(_ s: String) -> [String] { s.unicodeScalars.split(separator: " ").map { String(String.UnicodeScalarView($0)) } }
        let a = keys(plain)
        let b = keys(shifted)
        precondition(a.count == b.count, "unshifted and shifted rows differ in length")
        return zip(a, b).map { CharacterKey(output: $0, shifted: $1) }
    }

    /// TIS 820-2538 Kedmanee. ฃ/ฅ sit at the end of the home row, as on the iPhone's own Thai keyboard, so no row is
    /// wider than twelve keys.
    static let kedmanee: [[CharacterKey]] = [
        row("ๅ / - ภ ถ ุ ึ ค ต จ ข ช", "+ ๑ ๒ ๓ ๔ ู ฿ ๕ ๖ ๗ ๘ ๙"),
        row("ๆ ไ ำ พ ะ ั ี ร น ย บ ล", "๐ \" ฎ ฑ ธ ํ ๊ ณ ฯ ญ ฐ ,"),
        row("ฟ ห ก ด เ ้ ่ า ส ว ง ฃ", "ฤ ฆ ฏ โ ฌ ็ ๋ ษ ศ ซ . ฅ"),
        row("ผ ป แ อ ิ ื ท ม ใ ฝ", "( ) ฉ ฮ ฺ ์ ? ฒ ฬ ฦ"),
    ]

    static let numbers: [[CharacterKey]] = [
        row("1 2 3 4 5 6 7 8 9 0", "[ ] { } # % ^ * + ="),
        row("- / : ; ( ) ฿ & @ \"", "_ \\ | ~ < > $ € £ •"),
        row(". , ? ! '", ". , ? ! '"),
    ]
}
