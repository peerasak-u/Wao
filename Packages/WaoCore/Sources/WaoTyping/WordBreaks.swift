/// How well the dictionary explains a run of Thai typed without spaces: the fewest characters that no word covers,
/// over every way of splitting the run into words and loose characters. The run's start counts as a word break.
struct WordBreaks {
    /// `uncovered[i]` is the fewest of the run's first `i` characters left out when those `i` end at a word's end.
    let uncovered: [Int]
    /// The fewest left out of the whole run when its last piece may be a word still being typed.
    let open: Int

    init(_ run: some Collection<UInt8>, in model: TypingModel) {
        let run = Array(run)
        var uncovered = Array(0...run.count)
        var open = run.count
        for start in run.indices {
            uncovered[start + 1] = min(uncovered[start + 1], uncovered[start] + 1)
            var words = model.allWords
            for end in start..<run.count {
                words = model.narrow(words, at: end - start, to: run[end])
                if words.isEmpty { break }
                if model.length(of: words.lowerBound) == end - start + 1 {
                    uncovered[end + 1] = min(uncovered[end + 1], uncovered[start])
                }
                if end == run.count - 1 { open = min(open, uncovered[start]) }
            }
        }
        self.uncovered = uncovered
        self.open = min(open, uncovered[run.count])
    }
}
