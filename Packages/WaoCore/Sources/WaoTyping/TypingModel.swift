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
        let history = normalized(context, keep: order - 1)
        return nextCharacter(after: history.ids, atLineStart: history.atLineStart)
    }

    /// The same for a context already in symbol ids, of which only the last `order - 1` count.
    func nextCharacter(after ids: some Collection<UInt8>, atLineStart: Bool) -> NextCharacter {
        var history = Array(ids.suffix(order - 1))
        if atLineStart, history.count < order - 1 {
            history.insert(contentsOf: repeatElement(Self.space, count: order - 1 - history.count), at: 0)
        }
        var contexts: [UInt64] = []
        var backoff: [Float] = [0]
        for start in 0...history.count {
            let key = history[start...].reduce(UInt64(0)) { $0 << 7 | UInt64($1) }
            contexts.append(key)
            backoff.append(backoff.last! + (entry(key).map { bowBook[Int(bowIndex[$0])] } ?? 0))
        }
        return NextCharacter(model: self, contexts: contexts, backoff: backoff)
    }

    /// Up to `limit` words that continue the end of `context`, likeliest first. Thai is written without spaces
    /// between words, so the word so far may start at any point the dictionary can split everything typed before
    /// into words: ขอบ may be ขอบคุณ begun or ขอ then บอก begun, and both kinds compete. Once the text ends with a
    /// whole word of three letters or more, only words that go on from that word's start count, so ขอบคุณ is not
    /// offered ณรงค์, while ต้องก, which ends in the two-letter งก, still offers กิน. When the dictionary cannot
    /// split the text at all, the longest tail that starts a longer word. The language model ranks the words by
    /// how likely the rest of each is after `context`, with a bonus for the letters a longer word saves typing.
    public func completions(after context: some StringProtocol, limit: Int = 3) -> [Completion] {
        let run = self.run(before: context)
        let breaks = WordBreaks(run, in: self)
        let history = normalized(context, keep: order - 1)
        let clean = run.indices.filter { breaks.fits[$0].uncovered == 0 }
        let lastWord = clean.first { start in
            let words = words(startingWith: run[start...])
            return run.count - start >= Self.wholeWordLetters && !words.isEmpty
                && length(of: words.lowerBound) == run.count - start
        }
        let starts = clean.filter { $0 <= lastWord ?? run.count }
        var found = starts.flatMap { candidates(typed: run[$0...], after: history) }
        if found.isEmpty, lastWord == nil, let start = (max(0, run.count - maxWordLength)..<run.count).first(where: {
            !candidates(typed: run[$0...], after: history).isEmpty
        }) {
            found = candidates(typed: run[start...], after: history)
        }
        // Words that insert the same letters are one suggestion: it ranks as the best of them and shows the one
        // that takes in the most of what was typed, ขอบคุณ rather than คุณ.
        var byRemainder: [ArraySlice<UInt8>: (score: Float, shown: Candidate)] = [:]
        for candidate in found {
            let remainder = symbolIDs(of: candidate.word).dropFirst(candidate.typed)
            let best = byRemainder[remainder]
            byRemainder[remainder] = (max(best?.score ?? -.infinity, candidate.score),
                                      best.map { $0.shown.typed >= candidate.typed ? $0.shown : candidate } ?? candidate)
        }
        let ranked = byRemainder.values.sorted { a, b in a.score != b.score ? a.score > b.score : a.shown.word < b.shown.word }
        return ranked.prefix(limit).map { _, shown in
            let word = symbols(of: shown.word)
            return Completion(word: String(String.UnicodeScalarView(word)),
                              remainder: String(String.UnicodeScalarView(word.dropFirst(shown.typed))))
        }
    }

    /// A dictionary word that would finish `typed` letters already on the line, and how it ranks.
    private struct Candidate { let word: Int, typed: Int, score: Float }

    /// The most frequent words longer than `typed` that begin with it, scored.
    private func candidates(typed: ArraySlice<UInt8>, after history: (ids: [UInt8], atLineStart: Bool)) -> [Candidate] {
        let longer = words(startingWith: typed).filter { length(of: $0) > typed.count }
        let pool = Array(longer.sorted { wordFreq[$0] != wordFreq[$1] ? wordFreq[$0] > wordFreq[$1] : $0 < $1 }.prefix(Self.rankedWords))
        let rest = restScores(pool, dropping: typed.count, after: history.ids, atLineStart: history.atLineStart)
        return pool.map { word in
            let letters = Float(length(of: word) - typed.count)
            return Candidate(word: word, typed: typed.count,
                             score: rest[word]! + Self.letterBonus * letters + Self.frequencyWeight * Float(wordFreq[word]))
        }
    }

    /// Nats per letter a word adds and per step of its frequency byte, both chosen by wao-typing-eval's suggest mode.
    static let letterBonus: Float = 0.2
    static let frequencyWeight: Float = 0.01

    /// The shortest word that ends what is being typed; shorter ones are too often the start of something else.
    static let wholeWordLetters = 3
    /// How many of the most frequent candidates the language model ranks: a word begun with one letter has
    /// thousands.
    static let rankedWords = 48
    /// How far back a run of Thai is read for word breaks.
    static let runLength = 32

    /// The end of the line after its last space, as symbol ids, at most `runLength` of them.
    func run(before context: some StringProtocol) -> [UInt8] {
        Array(normalized(context, keep: Self.runLength).ids.reversed().prefix { $0 != Self.space }.reversed())
    }

    /// ln P of each word's rest, after its first `typed` symbols, following `history`. Words are scored in
    /// dictionary order so that each reuses what it shares with the one before.
    private func restScores(_ words: [Int], dropping typed: Int, after history: [UInt8], atLineStart: Bool) -> [Int: Float] {
        var scores: [Int: Float] = [:]
        var path = history
        var cumulative: [Float] = [0]
        for word in words.sorted() {
            let rest = symbolIDs(of: word).dropFirst(typed)
            let shared = zip(path.dropFirst(history.count), rest).prefix { $0 == $1 }.count
            path.removeLast(path.count - history.count - shared)
            cumulative.removeLast(cumulative.count - 1 - shared)
            for id in rest.dropFirst(shared) {
                cumulative.append(cumulative.last! + nextCharacter(after: path, atLineStart: atLineStart).logP(id))
                path.append(id)
            }
            scores[word] = cumulative.last!
        }
        return scores
    }

    var allWords: Range<Int> { 0..<wordFreq.count }

    /// The words in `range`, which all share their first `offset` symbols, whose next symbol is `symbol`. Words
    /// sort by their symbol bytes, so one that ends at `offset` sorts before the rest.
    func narrow(_ range: Range<Int>, at offset: Int, to symbol: UInt8) -> Range<Int> {
        func next(_ word: Int) -> Int {
            let at = Int(wordOffsets[word]) + offset
            return at < Int(wordOffsets[word + 1]) ? Int(wordBlob[at]) : -1
        }
        let lower = partition(range.lowerBound, range.upperBound) { next($0) < Int(symbol) }
        return lower..<partition(lower, range.upperBound) { next($0) <= Int(symbol) }
    }

    func words(startingWith prefix: some Collection<UInt8>) -> Range<Int> {
        prefix.enumerated().reduce(allWords) { narrow($0, at: $1.offset, to: $1.element) }
    }

    func length(of word: Int) -> Int { Int(wordOffsets[word + 1] - wordOffsets[word]) }

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

    private func symbolIDs(of word: Int) -> ArraySlice<UInt8> {
        ArraySlice(wordBlob[Int(wordOffsets[word])..<Int(wordOffsets[word + 1])])
    }

    private func symbols(of word: Int) -> [Unicode.Scalar] { symbolIDs(of: word).map { symbols[Int($0) - 1] } }

    /// The end of the current line as symbol ids, the way the builder normalised its training lines: anything off
    /// the keys is a space, runs of spaces are one, and a line starts without one.
    func normalized(_ context: some StringProtocol, keep: Int) -> (ids: [UInt8], atLineStart: Bool) {
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
        return logP(id)
    }

    func logP(_ id: UInt8) -> Float { model.logP(id, contexts: contexts, backoff: backoff) }
}

/// A word the suggestion bar offers.
public struct Completion: Equatable, Sendable {
    /// What the bar shows.
    public let word: String
    /// What tapping it inserts: the word minus what has already been typed.
    public let remainder: String
}
