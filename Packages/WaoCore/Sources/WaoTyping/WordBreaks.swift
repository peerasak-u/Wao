/// How well the dictionary explains a run of Thai typed without spaces: the fewest characters that no word covers,
/// over every way of splitting the run into words and loose characters, then the fewest pieces among those splits.
/// The run's start counts as a word break.
struct WordBreaks {
    /// How one split explains a run, better when less is left out and then when it takes fewer pieces.
    struct Fit: Comparable {
        var uncovered: Int
        var pieces: Int

        static func < (a: Fit, b: Fit) -> Bool { (a.uncovered, a.pieces) < (b.uncovered, b.pieces) }
    }

    /// `fits[i]` is the best split of the run's first `i` characters that ends at a word's end.
    let fits: [Fit]
    /// The best split of the whole run when its last piece may be a word still being typed.
    let open: Fit

    init(_ run: some Collection<UInt8>, in model: TypingModel) {
        let run = Array(run)
        var fits = (0...run.count).map { Fit(uncovered: $0, pieces: $0) }
        var open = Fit(uncovered: run.count, pieces: run.count)
        for start in run.indices {
            let here = fits[start]
            fits[start + 1] = min(fits[start + 1], Fit(uncovered: here.uncovered + 1, pieces: here.pieces + 1))
            var words = model.allWords
            for end in start..<run.count {
                words = model.narrow(words, at: end - start, to: run[end])
                if words.isEmpty { break }
                let word = Fit(uncovered: here.uncovered, pieces: here.pieces + 1)
                if model.length(of: words.lowerBound) == end - start + 1 { fits[end + 1] = min(fits[end + 1], word) }
                if end == run.count - 1 { open = min(open, word) }
            }
        }
        self.fits = fits
        self.open = min(open, fits[run.count])
    }
}
