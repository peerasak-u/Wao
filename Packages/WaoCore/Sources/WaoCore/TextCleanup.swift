import Foundation

/// The clean-up every transcription goes through, as an ordered list of pure text stages.
public struct TextCleanup: Sendable {
    public struct Stage: Sendable {
        public let name: String
        public let apply: @Sendable (String) -> String
    }

    public let stages: [Stage]

    public init(stages: [Stage]) {
        self.stages = stages
    }

    public func callAsFunction(_ text: String) -> String {
        stages.reduce(text) { $1.apply($0) }
    }

    public static let none = TextCleanup(stages: [])

    /// Order matters: acronyms become Latin before doubled letters and case are fixed, and spacing comes last so
    /// it also spaces what the corrections put in.
    public init(hotwords: Hotwords, corrections: Corrections) {
        self.init(stages: [
            Stage(name: "sara am", apply: { TextCleanup.saraAm($0) }),
            Stage(name: "Thai acronyms to Latin", apply: { Acronyms.toLatin($0) }),
            Stage(name: "doubled letters", apply: { hotwords.fixDoubledLetters($0) }),
            Stage(name: "canonical case", apply: { hotwords.canonicalCase($0).trimmingCharacters(in: .whitespaces) }),
            Stage(name: "corrections", apply: { corrections.apply($0) }),
            Stage(name: "Thai/Latin spacing", apply: { TextCleanup.spaceThaiLatin($0) }),
        ])
    }

    public static let standard = TextCleanup(hotwords: .bundled, corrections: .bundled)

    /// The model spells sara am as nikhahit + sara aa; the single code point is what search and spell-check expect.
    public static func saraAm(_ text: String) -> String {
        Corrections.replace(text, "\u{0E4D}\u{0E32}", with: "\u{0E33}")
    }

    /// Spaces Thai letters apart from touching Latin letters or digits ("ต้องhotfixด่วน" → "ต้อง hotfix ด่วน",
    /// "มี3คน" → "มี 3 คน"), the way mixed Thai text is written.
    public static func spaceThaiLatin(_ text: String) -> String {
        func latin(_ c: Unicode.Scalar) -> Bool { c.isASCIIAlphanumeric || c == "%" }
        var out = String.UnicodeScalarView()
        var prev: Unicode.Scalar?
        for c in text.unicodeScalars {
            if let p = prev, (p.isThai && latin(c) && c != "%") || (latin(p) && c.isThai) { out.append(" ") }
            out.append(c)
            prev = c
        }
        return String(out)
    }
}
