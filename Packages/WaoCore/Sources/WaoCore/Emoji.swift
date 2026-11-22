import Foundation

/// One emoji in the panel's grid.
public struct Emoji: Equatable, Hashable, Sendable {
    public let glyph: String
    /// Unicode's CLDR short name, which VoiceOver reads.
    public let name: String
    /// The five skin-tone variants, lightest first, or none.
    public let tones: [String]

    public static let toneNames = ["light skin tone", "medium-light skin tone", "medium skin tone",
                                   "medium-dark skin tone", "dark skin tone"]

    /// `tone` indexes `tones`; nil is the default yellow.
    public func glyph(tone: Int?) -> String { tone.map { tones[$0] } ?? glyph }

    public func name(tone: Int?) -> String { tone.map { "\(name): \(Self.toneNames[$0])" } ?? name }
}

/// The iOS emoji keyboard's categories, in its order. Frequently used comes first but is the user's, not Unicode's.
public enum EmojiCategory: String, CaseIterable, Sendable {
    case smileys, animals, food, activity, travel, objects, symbols, flags
}

/// Every emoji the panel offers, by category, read from emoji.txt (built by tools/build_emoji.py).
public struct EmojiCatalog: Sendable {
    public struct Section: Sendable {
        public let category: EmojiCategory
        public let emoji: [Emoji]
    }

    public let sections: [Section]
    /// Every glyph the panel can type, tone variants included, to its emoji and tone.
    private let index: [String: (emoji: Emoji, tone: Int?)]

    /// Read on first use, when the panel first opens, so typing never pays for it.
    public static let bundled: EmojiCatalog? = Bundle.module.url(forResource: "emoji", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        .flatMap(EmojiCatalog.init)

    public init?(_ text: String) {
        var sections: [Section] = []
        var category: EmojiCategory?
        var emoji: [Emoji] = []
        var index: [String: (emoji: Emoji, tone: Int?)] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t").map(String.init)
            if fields.count == 1 {
                if let category { sections.append(Section(category: category, emoji: emoji)) }
                guard let next = EmojiCategory(rawValue: fields[0]) else { return nil }
                category = next
                emoji = []
                continue
            }
            guard category != nil, fields.count == 2 || fields.count == 7 else { return nil }
            let entry = Emoji(glyph: fields[0], name: fields[1], tones: Array(fields.dropFirst(2)))
            emoji.append(entry)
            index[entry.glyph] = (entry, nil)
            for (tone, glyph) in entry.tones.enumerated() { index[glyph] = (entry, tone) }
        }
        if let category { sections.append(Section(category: category, emoji: emoji)) }
        guard sections.map(\.category) == EmojiCategory.allCases else { return nil }
        self.sections = sections
        self.index = index
    }

    /// The emoji a typed glyph came from, and which tone it was typed in.
    public func lookup(_ glyph: String) -> (emoji: Emoji, tone: Int?)? { index[glyph] }
}

/// What the user typed from the panel: the recent emoji, newest first, and the tone last picked for each emoji.
public struct EmojiHistory: Codable, Equatable, Sendable {
    public static let capacity = 30

    public private(set) var recent: [String] = []
    /// Base glyph to the variant last picked for it; the grid shows that one.
    public private(set) var tones: [String: String] = [:]

    public init() {}

    public mutating func use(_ emoji: Emoji, tone: Int?) {
        let glyph = emoji.glyph(tone: tone)
        recent.removeAll { $0 == glyph }
        recent.insert(glyph, at: 0)
        if recent.count > Self.capacity { recent.removeLast(recent.count - Self.capacity) }
        tones[emoji.glyph] = tone == nil ? nil : glyph
    }

    /// What the grid shows for `emoji`: the tone last picked for it, else the default.
    public func shown(_ emoji: Emoji) -> String { tones[emoji.glyph] ?? emoji.glyph }
}
