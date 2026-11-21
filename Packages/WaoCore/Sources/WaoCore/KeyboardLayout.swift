import Foundation

/// A character key: what it types unshifted and shifted.
public struct CharacterKey: Equatable, Sendable {
    public let output: String
    public let shifted: String

    public func text(shifted isShifted: Bool) -> String { isShifted ? shifted : output }
}

public enum KeyboardLayout: String, CaseIterable, Sendable {
    case thai
    case english

    /// The dictation language follows the layout on screen.
    public var language: Language {
        switch self {
        case .thai: .thai
        case .english: .thaiEnglishMix
        }
    }

    /// Caption of the key that switches to the other layout.
    public var switchLabel: String {
        switch self {
        case .thai: "ABC"
        case .english: "กขค"
        }
    }

    public var spaceLabel: String {
        switch self {
        case .thai: "เว้นวรรค"
        case .english: "space"
        }
    }

    public var other: KeyboardLayout { self == .thai ? .english : .thai }

    public var rows: [[CharacterKey]] {
        switch self {
        case .thai: Self.kedmanee
        case .english: Self.qwerty
        }
    }

    /// Splits on scalars because a Thai combining mark after a space joins the space's grapheme cluster.
    private static func row(_ plain: String, _ shifted: String) -> [CharacterKey] {
        func keys(_ s: String) -> [String] { s.unicodeScalars.split(separator: " ").map { String(String.UnicodeScalarView($0)) } }
        let a = keys(plain)
        let b = keys(shifted)
        precondition(a.count == b.count, "unshifted and shifted rows differ in length")
        return zip(a, b).map { CharacterKey(output: $0, shifted: $1) }
    }

    /// TIS 820-2538 Kedmanee, the standard Thai layout, as its four rows.
    static let kedmanee: [[CharacterKey]] = [
        row("ๅ / - ภ ถ ุ ึ ค ต จ ข ช", "+ ๑ ๒ ๓ ๔ ู ฿ ๕ ๖ ๗ ๘ ๙"),
        row("ๆ ไ ำ พ ะ ั ี ร น ย บ ล ฃ", "๐ \" ฎ ฑ ธ ํ ๊ ณ ฯ ญ ฐ , ฅ"),
        row("ฟ ห ก ด เ ้ ่ า ส ว ง", "ฤ ฆ ฏ โ ฌ ็ ๋ ษ ศ ซ ."),
        row("ผ ป แ อ ิ ื ท ม ใ ฝ", "( ) ฉ ฮ ฺ ์ ? ฒ ฬ ฦ"),
    ]

    static let qwerty: [[CharacterKey]] = [
        row("1 2 3 4 5 6 7 8 9 0", "! @ # $ % & * ( ) -"),
        row("q w e r t y u i o p", "Q W E R T Y U I O P"),
        row("a s d f g h j k l", "A S D F G H J K L"),
        row("z x c v b n m , .", "Z X C V B N M ? '"),
    ]
}
