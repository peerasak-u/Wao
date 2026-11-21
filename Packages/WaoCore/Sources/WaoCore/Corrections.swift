import Foundation

/// Replacements for words the model keeps hearing the same wrong way ("อินฟา" → "infra").
public struct Corrections: Sendable {
    /// Longest heard form first, so a longer phrase wins over a word inside it.
    public let pairs: [(heard: String, wanted: String)]

    /// Lines `heard = wanted`, several heard forms separated by commas; blank lines and lines starting with #
    /// are skipped.
    public init(list: String) {
        var pairs: [(heard: String, wanted: String)] = []
        for line in list.components(separatedBy: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let wanted = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            for heard in line[..<eq].split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !heard.isEmpty {
                pairs.append((heard, wanted))
            }
        }
        self.pairs = pairs.enumerated()
            .sorted { ($0.element.heard.unicodeScalars.count, $1.offset) > ($1.element.heard.unicodeScalars.count, $0.offset) }
            .map(\.element)
    }

    public func apply(_ text: String) -> String {
        pairs.reduce(text) { Self.replace($0, $1.heard, with: $1.wanted) }
    }

    /// Replaces every `from` with `to`. An ASCII `from` matches only a whole word, in any case; other text matches
    /// anywhere, since Thai has no spaces between words. A Latin `to` touching a Thai letter gets a space on that
    /// side ("ใช้จีพียู" → "ใช้ GPU").
    public static func replace(_ text: String, _ from: String, with to: String) -> String {
        let t = Array(text.unicodeScalars)
        let f = Array(from.unicodeScalars)
        let ascii = f.allSatisfy(\.isASCII)
        let ranges = ascii ? t.map(\.asciiLowercased).wholeWordMatches(of: f.map(\.asciiLowercased)) : t.matches(of: f)
        guard !ranges.isEmpty else { return text }
        let latinStart = to.unicodeScalars.first?.isASCIIAlphanumeric ?? false
        let latinEnd = to.unicodeScalars.last?.isASCIIAlphanumeric ?? false
        var out = String.UnicodeScalarView()
        var last = 0
        for r in ranges {
            out.append(contentsOf: t[last..<r.lowerBound])
            if latinStart, r.lowerBound > 0, t[r.lowerBound - 1].isThai { out.append(" ") }
            out.append(contentsOf: to.unicodeScalars)
            if latinEnd, r.upperBound < t.count, t[r.upperBound].isThai { out.append(" ") }
            last = r.upperBound
        }
        out.append(contentsOf: t[last...])
        return String(out)
    }
}

extension Corrections {
    public static let bundled = Corrections(list: BundledLists.corrections)
}

/// The default lists, copied from PoodPim (see Resources/THIRD_PARTY_NOTICES).
public enum BundledLists {
    public static let vocabulary = load("vocabulary")
    public static let corrections = load("corrections")
    public static var notice: String { load("THIRD_PARTY_NOTICES", extension: nil) }

    private static func load(_ name: String, extension ext: String? = "txt") -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { preconditionFailure("\(name) missing from the WaoCore bundle") }
        return text
    }
}
