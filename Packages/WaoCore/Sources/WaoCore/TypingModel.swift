import Foundation

/// The Thai character language model and word list behind tap decoding and the suggestion bar, read in place from
/// `thai-typing.bin` (built by tools/build_typing_model.py, which documents the format). Memory-mapped and never
/// written, so the keyboard's footprint is only the clean pages a lookup touches.
public final class TypingModel: @unchecked Sendable {
    public enum LoadError: Error { case unreadable(String), invalid(String) }

    /// Absent or corrupt, the keyboard types the key under the finger and shows no suggestions.
    public static let bundled: TypingModel? = Bundle.module.url(forResource: "thai-typing", withExtension: "bin")
        .flatMap { try? TypingModel(contentsOf: $0) }

    public let order: Int
    /// Symbol id `i + 1` is `symbols[i]`; the first is the space.
    public let symbols: [Unicode.Scalar]
    let maxWordLength: Int

    private let mapping: UnsafeMutableRawPointer
    private let length: Int
    private let ids: [Unicode.Scalar: UInt8]
    private let logpBook: [Float]
    private let bowBook: [Float]
    private let keys: UnsafeBufferPointer<UInt64>
    private let logpIndex: UnsafeBufferPointer<UInt8>
    private let bowIndex: UnsafeBufferPointer<UInt8>
    private let wordOffsets: UnsafeBufferPointer<UInt32>
    private let wordBlob: UnsafeBufferPointer<UInt8>
    private let wordFreq: UnsafeBufferPointer<UInt8>
    private static let space: UInt8 = 1

    public init(contentsOf url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw LoadError.unreadable(url.path) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 72 else { throw LoadError.invalid("too short") }
        length = Int(info.st_size)
        guard let base = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0), base != MAP_FAILED else {
            throw LoadError.unreadable(url.path)
        }
        mapping = base
        let raw = UnsafeRawBufferPointer(start: base, count: length)
        func u32(_ at: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: at, as: UInt32.self)) }
        func section<T>(_ offsetField: Int, _ count: Int, _: T.Type) throws -> UnsafeBufferPointer<T> {
            let offset = u32(offsetField)
            guard offset % MemoryLayout<T>.alignment == 0, offset + count * MemoryLayout<T>.stride <= raw.count else {
                throw LoadError.invalid("section at \(offsetField) out of bounds")
            }
            return UnsafeBufferPointer(start: base.advanced(by: offset).bindMemory(to: T.self, capacity: count), count: count)
        }
        do {
            guard raw.prefix(8).elementsEqual("WAOTYPE1".utf8), u32(8) == 1 else { throw LoadError.invalid("not a version 1 typing model") }
            order = Int(raw[12])
            let symbolCount = Int(raw[13])
            maxWordLength = Int(raw[14])
            guard (1...9).contains(order), symbolCount < 128 else { throw LoadError.invalid("order \(order), \(symbolCount) symbols") }
            let entryCount = u32(16), wordCount = u32(20)
            symbols = try section(24, symbolCount, UInt32.self).map { Unicode.Scalar($0) ?? " " }
            logpBook = Array(try section(28, 256, Float.self))
            bowBook = Array(try section(32, 256, Float.self))
            keys = try section(36, entryCount, UInt64.self)
            logpIndex = try section(40, entryCount, UInt8.self)
            bowIndex = try section(44, entryCount, UInt8.self)
            wordOffsets = try section(48, wordCount + 1, UInt32.self)
            wordBlob = try section(52, wordOffsets.last.map { Int($0) } ?? 0, UInt8.self)
            wordFreq = try section(56, wordCount, UInt8.self)
        } catch {
            munmap(base, length)
            throw error
        }
        ids = Dictionary(uniqueKeysWithValues: symbols.enumerated().map { ($1, UInt8($0 + 1)) })
    }

    deinit { munmap(mapping, length) }

    /// What the file says it was built from, for the credits and for checking a rebuild.
    public var buildInfo: String {
        let raw = UnsafeRawBufferPointer(start: mapping, count: length)
        let offset = Int(raw.loadUnaligned(fromByteOffset: 60, as: UInt32.self))
        let count = Int(raw.loadUnaligned(fromByteOffset: 64, as: UInt32.self))
        return String(decoding: raw[offset..<offset + count], as: UTF8.self)
    }

    /// The distribution over the next character, for one context, ready to score every key.
    public func nextCharacter(after context: some StringProtocol) -> NextCharacter {
        var history = normalized(context, keep: order - 1)
        if history.atLineStart, history.ids.count < order - 1 {
            history.ids.insert(contentsOf: repeatElement(Self.space, count: order - 1 - history.ids.count), at: 0)
        }
        var contexts: [UInt64] = []
        var backoff: [Float] = [0]
        for start in 0...history.ids.count {
            let key = history.ids[start...].reduce(UInt64(0)) { $0 << 7 | UInt64($1) }
            contexts.append(key)
            backoff.append(backoff.last! + (entry(key).map { bowBook[Int(bowIndex[$0])] } ?? 0))
        }
        return NextCharacter(model: self, contexts: contexts, backoff: backoff)
    }

    /// Up to `limit` words that continue the end of `context`, most frequent first. Thai is written without spaces
    /// between words, so the longest tail of the context that starts some longer word is taken as the word so far.
    public func completions(after context: some StringProtocol, limit: Int = 3) -> [Completion] {
        let history = normalized(context, keep: maxWordLength)
        let typed = Array(history.ids.reversed().prefix { $0 != Self.space }.reversed())
        for length in stride(from: typed.count, through: 1, by: -1) {
            let prefix = typed.suffix(length)
            let lower = partition(0, wordFreq.count) { compare(word: $0, prefix) < 0 }
            let upper = partition(lower, wordFreq.count) { compare(word: $0, prefix) <= 0 }
            let longer = (lower..<upper).filter { wordOffsets[$0 + 1] - wordOffsets[$0] > length }
            guard !longer.isEmpty else { continue }
            let best = longer.sorted { wordFreq[$0] != wordFreq[$1] ? wordFreq[$0] > wordFreq[$1] : $0 < $1 }
            return best.prefix(limit).map { index in
                let word = symbols(of: index)
                return Completion(word: String(String.UnicodeScalarView(word)), remainder: String(String.UnicodeScalarView(word.dropFirst(length))))
            }
        }
        return []
    }

    func logP(_ id: UInt8, contexts: [UInt64], backoff: [Float]) -> Float {
        for (level, context) in contexts.enumerated() {
            if let index = entry(context << 7 | UInt64(id)) {
                return backoff[level] + logpBook[Int(logpIndex[index])]
            }
        }
        return backoff[contexts.count] - log(Float(symbols.count))
    }

    func id(of text: String) -> UInt8? {
        let scalars = text.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return nil }
        return ids[scalar]
    }

    private func entry(_ key: UInt64) -> Int? {
        let index = partition(0, keys.count) { keys[$0] < key }
        return index < keys.count && keys[index] == key ? index : nil
    }

    /// The first index in `lower..<upper` where `isBefore` turns false.
    private func partition(_ lower: Int, _ upper: Int, _ isBefore: (Int) -> Bool) -> Int {
        var lower = lower, upper = upper
        while lower < upper {
            let mid = (lower + upper) / 2
            if isBefore(mid) { lower = mid + 1 } else { upper = mid }
        }
        return lower
    }

    private func compare(word index: Int, _ prefix: ArraySlice<UInt8>) -> Int {
        let start = Int(wordOffsets[index]), end = Int(wordOffsets[index + 1])
        for (offset, symbol) in prefix.enumerated() {
            guard start + offset < end else { return -1 }
            let byte = wordBlob[start + offset]
            if byte != symbol { return byte < symbol ? -1 : 1 }
        }
        return 0
    }

    private func symbols(of word: Int) -> [Unicode.Scalar] {
        (Int(wordOffsets[word])..<Int(wordOffsets[word + 1])).map { symbols[Int(wordBlob[$0]) - 1] }
    }

    /// The end of the current line as symbol ids, the way the builder normalised its training lines: anything off
    /// the keys is a space, runs of spaces are one, and a line starts without one.
    private func normalized(_ context: some StringProtocol, keep: Int) -> (ids: [UInt8], atLineStart: Bool) {
        var reversed: [UInt8] = []
        var atLineStart = true
        for scalar in context.unicodeScalars.reversed() {
            if scalar == "\n" || scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}" { break }
            let id = ids[scalar] ?? Self.space
            if id == Self.space, reversed.last == Self.space { continue }
            if reversed.count == keep { atLineStart = false; break }
            reversed.append(id)
        }
        if atLineStart { while reversed.last == Self.space { reversed.removeLast() } }
        return (reversed.reversed(), atLineStart)
    }
}

/// The language model's view of one context: `logP` scores any key's text in a few binary searches.
public struct NextCharacter: Sendable {
    let model: TypingModel
    /// The context's suffixes as entry keys, longest first, ending with the empty context.
    let contexts: [UInt64]
    /// ln of the backoff weights paid before trying each of `contexts`, and after the last.
    let backoff: [Float]

    /// ln P(text | context); `-infinity` for anything that is not one of the model's symbols.
    public func logP(_ text: String) -> Float {
        guard let id = model.id(of: text) else { return -.infinity }
        return model.logP(id, contexts: contexts, backoff: backoff)
    }
}

/// A word the suggestion bar offers.
public struct Completion: Equatable, Sendable {
    /// What the bar shows.
    public let word: String
    /// What tapping it inserts: the word minus what has already been typed.
    public let remainder: String
}
