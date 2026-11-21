import Foundation

/// English terms to favour while decoding, in a character trie keyed lower-case without spaces, so a term
/// matches however the model splits it into pieces ("Nvidia" = "N" + "vid" + "ia" or "▁Nv" + "idia").
/// Only Latin spellings go in: boosting a Thai spelling ("จีพียู") would reinforce the wrong output.
public struct Hotwords: Sendable {
    struct Node: Sendable {
        var children: [(Unicode.Scalar, Int32)] = []
        var end = false
    }

    /// Where a hypothesis is in the trie, and the bonus it would lose if the match broke.
    public struct State: Hashable, Sendable {
        var node: Int32 = 0
        public internal(set) var pending: Float = 0

        public init() {}

        init(node: Int32, pending: Float) {
            self.node = node
            self.pending = pending
        }
    }

    private(set) var nodes = [Node()]
    public private(set) var words: [String] = []

    /// One term per line; blank lines and lines starting with # are skipped.
    public init(list: String) {
        self.init(words: list.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })
    }

    public init(words terms: [String]) {
        for word in terms {
            var node = 0
            for c in Self.key(word) {
                if let next = nodes[node].children.first(where: { $0.0 == c }) {
                    node = Int(next.1)
                } else {
                    nodes.append(Node())
                    nodes[node].children.append((c, Int32(nodes.count - 1)))
                    node = nodes.count - 1
                }
            }
            if node != 0 {
                nodes[node].end = true
                words.append(word)
            }
        }
    }

    public var isEmpty: Bool { words.isEmpty }

    static func key(_ s: String) -> [Unicode.Scalar] {
        s.unicodeScalars
            .filter { !$0.properties.isWhitespace && $0 != "\u{2581}" }
            .flatMap { String($0).lowercased().unicodeScalars }
    }

    private func walk(from: Int, _ key: [Unicode.Scalar]) -> Int? {
        var node = from
        for c in key {
            guard let next = nodes[node].children.first(where: { $0.0 == c }) else { return nil }
            node = Int(next.1)
        }
        return node
    }

    /// After emitting `piece`: the new state and the change to the hypothesis's score.
    public func advance(_ state: State, piece: String, bonus: Float) -> (State, Float) {
        let k = Self.key(piece)
        if isEmpty || k.isEmpty { return (state, 0) }
        func step(_ node: Int, _ pending: Float) -> (State, Float) {
            // A whole term keeps its bonus for good; the state stays so a longer term can go on.
            nodes[node].end
                ? (State(node: Int32(node), pending: 0), bonus)
                : (State(node: Int32(node), pending: pending + bonus), bonus)
        }
        if let n = walk(from: Int(state.node), k) { return step(n, state.pending) }
        if let n = walk(from: 0, k) {
            let (s, d) = step(n, 0)
            return (s, d - state.pending)
        }
        return (State(), -state.pending)
    }

    /// Acronyms the model wrote with a letter doubled ("MVPP", "GPUU", "CCPU": it spells them letter by letter
    /// and sometimes says one twice) become the known one, if dropping one doubled letter gives a known acronym.
    public func fixDoubledLetters(_ text: String) -> String {
        func known(_ w: String) -> Bool {
            Acronyms.all.contains { $0.caseInsensitiveCompare(w) == .orderedSame } || words.contains(w)
        }
        var out = String.UnicodeScalarView()
        var word: [Unicode.Scalar] = []
        func flush() {
            let w = String(String.UnicodeScalarView(word))
            if word.count >= 3, word.allSatisfy({ ("A"..."Z").contains($0) }), !known(w),
               let fixed = (1..<word.count).lazy
                   .filter({ word[$0] == word[$0 - 1] })
                   .map({ i in String(String.UnicodeScalarView(word.enumerated().filter { $0.offset != i }.map(\.element))) })
                   .first(where: known) {
                out.append(contentsOf: fixed.unicodeScalars)
            } else {
                out.append(contentsOf: word)
            }
            word.removeAll()
        }
        for c in text.unicodeScalars {
            if c.isASCIIAlphanumeric {
                word.append(c)
            } else {
                flush()
                out.append(c)
            }
        }
        flush()
        return String(out)
    }

    /// Writes terms the way the list does ("nvidia" → "Nvidia") where they stand as whole words.
    public func canonicalCase(_ text: String) -> String {
        var out = Array(text.unicodeScalars)
        for w in words where w.unicodeScalars.allSatisfy(\.isASCII) {
            let wanted = Array(w.unicodeScalars)
            let needle = wanted.map(\.asciiLowercased)
            for range in out.map(\.asciiLowercased).wholeWordMatches(of: needle).reversed() {
                out.replaceSubrange(range, with: wanted)
            }
        }
        return String(String.UnicodeScalarView(out))
    }
}

extension Hotwords {
    public static let bundled = Hotwords(list: BundledLists.vocabulary)
}

/// Tech acronyms Thai speakers say letter by letter, which the model often writes in Thai ("จีพียู") although
/// people write them in Latin letters ("GPU").
enum Acronyms {
    static let all = [
        "AI", "AGI", "API", "AWS", "CPU", "GPU", "TPU", "NPU", "CEO", "CTO", "CFO", "COO", "CMO", "IT", "MIT", "AMD",
        "UI", "UX", "PC", "HR", "PR", "KPI", "OKR", "SQL", "PDF", "USB", "LLM", "ML", "NLP", "IoT", "VR", "AR", "SME",
        "EV", "QA", "IPO", "ROI",
    ]

    static func letterNames(_ c: Character) -> [String] {
        switch c.uppercased() {
        case "A": ["เอ"]
        case "B": ["บี"]
        case "C": ["ซี"]
        case "D": ["ดี"]
        case "E": ["อี"]
        case "F": ["เอฟ"]
        case "G": ["จี"]
        case "H": ["เอช", "เฮช"]
        case "I": ["ไอ"]
        case "J": ["เจ"]
        case "K": ["เค"]
        case "L": ["แอล", "แอว"]
        case "M": ["เอ็ม"]
        case "N": ["เอ็น", "เอน"]
        case "O": ["โอ"]
        case "P": ["พี"]
        case "Q": ["คิว"]
        case "R": ["อาร์", "อา"]
        case "S": ["เอส"]
        case "T": ["ที"]
        case "U": ["ยู"]
        case "V": ["วี"]
        case "W": ["ดับเบิลยู", "ดับบลิว"]
        case "X": ["เอ็กซ์", "เอ็ก"]
        case "Y": ["วาย"]
        case "Z": ["แซด"]
        default: []
        }
    }

    /// Every Thai spelling of every acronym, longest first.
    static let thaiSpellings: [(thai: String, latin: String)] = {
        var table: [(thai: String, latin: String)] = []
        for a in all {
            var spellings = [""]
            for c in a {
                spellings = spellings.flatMap { s in letterNames(c).map { s + $0 } }
            }
            // Short ones ("ดี", "ที", "ไอ") are ordinary Thai words.
            table += spellings.filter { $0.unicodeScalars.count >= 4 }.map { ($0, a) }
        }
        return table.enumerated()
            .sorted { ($0.element.thai.unicodeScalars.count, $1.offset) > ($1.element.thai.unicodeScalars.count, $0.offset) }
            .map(\.element)
    }()

    static func toLatin(_ text: String) -> String {
        var out = text
        for (thai, latin) in thaiSpellings {
            out = Corrections.replace(out, thai, with: latin)
        }
        return out
    }
}

extension Unicode.Scalar {
    var isASCIIAlphanumeric: Bool { ("a"..."z").contains(self) || ("A"..."Z").contains(self) || ("0"..."9").contains(self) }
    var isThai: Bool { ("\u{0E00}"..."\u{0E7F}").contains(self) }
    var asciiLowercased: Unicode.Scalar { ("A"..."Z").contains(self) ? Unicode.Scalar(value + 32)! : self }
}

extension Array where Element == Unicode.Scalar {
    func matches(of needle: [Unicode.Scalar]) -> [Range<Int>] {
        guard !needle.isEmpty, needle.count <= count else { return [] }
        var found: [Range<Int>] = []
        var i = 0
        while i + needle.count <= count {
            if self[i..<(i + needle.count)].elementsEqual(needle) {
                found.append(i..<(i + needle.count))
                i += needle.count
            } else {
                i += 1
            }
        }
        return found
    }

    /// Matches not touching an ASCII letter or digit on either side.
    func wholeWordMatches(of needle: [Unicode.Scalar]) -> [Range<Int>] {
        matches(of: needle).filter { r in
            !(r.lowerBound > 0 && self[r.lowerBound - 1].isASCIIAlphanumeric)
                && !(r.upperBound < count && self[r.upperBound].isASCIIAlphanumeric)
        }
    }
}
