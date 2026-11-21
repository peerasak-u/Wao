import Foundation

public struct VocabularyGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var words: [String]

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, words: [String] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.words = words
    }
}

/// The user's hotwords, in groups that can be switched off without deleting their words.
public struct VocabularyBook: Codable, Hashable, Sendable {
    public var groups: [VocabularyGroup]

    public init(groups: [VocabularyGroup]) {
        self.groups = groups
    }

    /// One group per `# heading` in a one-word-per-line list. A heading is a `#` line followed directly by a
    /// word, so the file's opening guidance and licence lines don't become groups.
    public init(seedList: String) {
        var groups: [VocabularyGroup] = []
        var lastComment: String?
        for line in seedList.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.isEmpty {
                lastComment = nil
            } else if line.hasPrefix("#") {
                lastComment = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            } else {
                if let name = lastComment {
                    groups.append(VocabularyGroup(name: name))
                } else if groups.isEmpty {
                    groups.append(VocabularyGroup(name: "คำศัพท์"))
                }
                lastComment = nil
                groups[groups.count - 1].words.append(line)
            }
        }
        self.groups = groups
    }

    public static var bundled: VocabularyBook { VocabularyBook(seedList: BundledLists.vocabulary) }

    /// Words of the enabled groups, each once, in the spelling met first.
    public var effectiveWords: [String] {
        var seen = Set<String>()
        return groups.filter(\.isEnabled).flatMap(\.words).filter { seen.insert($0.lowercased()).inserted }
    }

    public var hotwords: Hotwords { Hotwords(words: effectiveWords) }

    public func contains(_ word: String) -> Bool {
        let key = word.lowercased()
        return groups.contains { $0.words.contains { $0.lowercased() == key } }
    }

    public struct ImportPreview: Equatable, Sendable {
        public var added: [String]
        public var duplicates: [String]
    }

    /// Words from pasted text, separated by commas or new lines; what is already anywhere in the book, or
    /// earlier in the same text, is a duplicate.
    public func previewImport(_ text: String) -> ImportPreview {
        var preview = ImportPreview(added: [], duplicates: [])
        var seen = Set<String>()
        for word in Self.parseWords(text) {
            if contains(word) || !seen.insert(word.lowercased()).inserted {
                preview.duplicates.append(word)
            } else {
                preview.added.append(word)
            }
        }
        return preview
    }

    /// Adds what `previewImport` would add to the group; returns how many words were added.
    @discardableResult
    public mutating func importWords(_ text: String, into groupID: VocabularyGroup.ID) -> Int {
        guard let i = groups.firstIndex(where: { $0.id == groupID }) else { return 0 }
        let added = previewImport(text).added
        groups[i].words += added
        return added.count
    }

    static func parseWords(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",，、")) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
