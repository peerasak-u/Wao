import CoreGraphics
import Foundation
import WaoCore

let usage = """
    wao-typing-eval [fixed|speed|sweep|latency|examples|suggest|retype|retype-sweep|all] [--model FILE] [--seeds N] [--sigma PT...]
                    [--lambda L --slack NATS --window TOUCHES --beam N --reach PT]

    Replays the held-out lines in Tests/WaoCoreTests/Fixtures as noisy taps on the Kedmanee grid a 390 pt iPhone shows and
    prints JSON lines comparing the geometric keyboard with tap decoders:
      fixed     fixed touch noise (--sigma, default 7), the research simulation's decoder table
      speed     noise that grows with typing speed, per speed bucket: fixed-sigma decoders against TapTuning.shipped
      sweep     the speed mix over a grid of tunings, best first
      latency   time per decoded tap and per suggestion lookup
      examples  taps that land on the wrong key and come out right even when typed slowly
      retype    the speed mix typed with TapTuning.shipped, then with retyping after every tap as well; and lines
                typed with every tap on its key's centre, which retyping must leave alone. RetypeTuning.shipped,
                or the tuning the flags give
      retype-sweep  the same over a grid of retype tunings, one seed each
      suggest   how often the suggestion bar, read after each Thai letter of a line, offers what the line types next
    `all` (the default) runs everything but the sweep. Run it built for release.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n\n\(usage)\n".utf8))
    exit(2)
}

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let fixtures = here.appendingPathComponent("../../Tests/WaoCoreTests/Fixtures").standardized
var modelPath = here.appendingPathComponent("../WaoCore/Resources/thai-typing.bin").standardized.path
var command = "all"
var seeds = 3
var sigmas: [CGFloat] = [7]
var retypeTuning = RetypeTuning.shipped
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    func value<T>(_ parse: (String) -> T?) -> T {
        guard let v = args.popFirst().flatMap(parse) else { fail("\(arg) needs a valid value") }
        return v
    }
    switch arg {
    case "--model": modelPath = value { $0 }
    case "--lambda": retypeTuning.lambda = value { Float($0) }
    case "--slack": retypeTuning.slack = value { Float($0) }
    case "--window": retypeTuning.window = value { Int($0) }
    case "--beam": retypeTuning.beam = value { Int($0) }
    case "--reach": retypeTuning.reach = value { Double($0).map { CGFloat($0) } }
    case "--seeds": seeds = value { Int($0) }
    case "--sigma":
        sigmas = []
        while let next = args.first, let value = Double(next) {
            sigmas.append(CGFloat(value))
            args.removeFirst()
        }
    case "fixed", "speed", "sweep", "latency", "examples", "suggest", "retype", "retype-sweep", "all": command = arg
    default: fail("unknown argument \(arg)")
    }
}

let model: TypingModel
do { model = try TypingModel(contentsOf: URL(fileURLWithPath: modelPath)) } catch { fail("cannot open \(modelPath): \(error)") }
let replay = Replay(model: model)
let tests: [(name: String, lines: [String])] = ["chat", "formal"].map { name in
    let url = fixtures.appendingPathComponent("typing-holdout-\(name).txt")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { fail("cannot read \(url.path)") }
    return (name, text.split(separator: "\n").map(String.init))
}

func emit(_ fields: KeyValuePairs<String, Any>) {
    let object = Dictionary(fields.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
}

func round(_ value: Double, _ places: Int) -> Double {
    let scale = pow(10, Double(places))
    return (value * scale).rounded() / scale
}

/// The true touch spread of the speed mix: 9 pt when hurried, 4 pt when deliberate (the simulation's assumption).
func trueSigma(_ interval: TimeInterval) -> Double { 4 + 5 * min(1, max(0, (0.6 - interval) / 0.45)) }

func bucket(_ interval: TimeInterval) -> String { interval < 0.25 ? "fast <0.25s" : interval > 0.45 ? "slow >0.45s" : "medium" }

func runFixed() {
    for sigma in sigmas {
        let decoders: [(String, Decoder)] = [
            ("baseline", .geometric),
            ("bayes lam0.4", .decoded(.fixed(sigma: sigma, lambda: 0.4))),
            ("bayes lam0.5 anchor0.5", .decoded(.fixed(sigma: sigma, lambda: 0.5, anchor: 0.5))),
            ("bayes lam0.6", .decoded(.fixed(sigma: sigma, lambda: 0.6))),
            ("bayes lam0.6 anchor0.5", .decoded(.fixed(sigma: sigma, lambda: 0.6, anchor: 0.5))),
            ("bayes lam1", .decoded(.fixed(sigma: sigma, lambda: 1))),
            ("bayes lam1 anchor0.5", .decoded(.fixed(sigma: sigma, lambda: 1, anchor: 0.5))),
            ("bayes lam1 anchor0.3", .decoded(.fixed(sigma: sigma, lambda: 1, anchor: 0.3))),
            ("bayes lam1 sigma x0.7", .decoded(.fixed(sigma: sigma * 0.7, lambda: 1))),
            ("bayes lam1 sigma x1.4", .decoded(.fixed(sigma: sigma * 1.4, lambda: 1))),
            ("bayes lam1.5", .decoded(.fixed(sigma: sigma, lambda: 1.5))),
        ]
        for test in tests {
            var rates = Array(repeating: [Double](), count: decoders.count)
            var totals = Array(repeating: Tally(), count: decoders.count)
            for seed in 0..<seeds {
                var rng = SplitMix64(seed: UInt64(1000 + seed))
                let lines = test.lines.map { replay.taps($0, rng: &rng) { _ in (.infinity, Double(sigma)) } }
                for (d, decoder) in decoders.enumerated() {
                    let tally = tallies(decoder.1, over: lines).values.reduce(Tally(), +)
                    rates[d].append(tally.errorRate)
                    totals[d] = totals[d] + tally
                }
            }
            let base = rates[0].reduce(0, +) / Double(seeds)
            for (d, decoder) in decoders.enumerated() {
                let mean = rates[d].reduce(0, +) / Double(seeds)
                let sd = (rates[d].map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(seeds)).squareRoot()
                emit([
                    "mode": "fixed", "sigma": Double(sigma), "test": test.name, "decoder": decoder.0,
                    "err_pct": round(100 * mean, 2), "err_sd": round(100 * sd, 2),
                    "rel_reduction_pct": round(100 * (1 - mean / base), 1),
                    "fixed": round(Double(totals[d].fixed) / Double(seeds), 1),
                    "induced": round(Double(totals[d].induced) / Double(seeds), 1),
                    "taps": totals[d].taps / seeds,
                ])
            }
        }
    }
}

/// Lines typed by a mix of fast, medium and slow typists (the simulation's speed.py), the same taps for every decoder.
func speedMix(_ lines: [String], seed: Int) -> [[Tap?]] {
    var rng = SplitMix64(seed: UInt64(100 + seed))
    return lines.map { line in
        let mu = [0.17, 0.30, 0.55].randomElement(using: &rng)!
        return replay.taps(line, rng: &rng) { rng in
            let interval = exp(log(mu) + 0.35 * rng.gaussian())
            return (interval, trueSigma(interval))
        }
    }
}

func tallies(_ decoder: Decoder, over taps: [[Tap?]]) -> [String: Tally] {
    var byBucket: [String: Tally] = [:]
    for line in taps {
        let geometric = replay.decode(line, with: .geometric), decoded = replay.decode(line, with: decoder)
        for (i, tap) in line.enumerated() {
            guard let tap else { continue }
            byBucket[bucket(tap.interval), default: Tally()].add(intended: tap.intended, geometric: geometric[i], decoded: decoded[i])
        }
    }
    return byBucket
}

func runSpeed() {
    var scaled = TapTuning.shipped
    scaled.sigmaFast *= 1.2
    scaled.sigmaSlow *= 1.2
    let decoders: [(String, Decoder)] = [
        ("baseline", .geometric),
        ("fixed sigma 7 lam0.5", .decoded(.fixed(sigma: 7, lambda: 0.5))),
        ("fixed sigma 7 lam\(TapTuning.shipped.lambda) anchor\(TapTuning.shipped.anchor)",
         .decoded(.fixed(sigma: 7, lambda: TapTuning.shipped.lambda, anchor: TapTuning.shipped.anchor))),
        ("shipped", .decoded(.shipped)),
        ("shipped, sigma misestimated x1.2", .decoded(scaled)),
    ]
    for test in tests {
        let sets = (0..<seeds).map { speedMix(test.lines, seed: $0) }
        for (name, decoder) in decoders {
            var byBucket: [String: Tally] = [:]
            for taps in sets { byBucket.merge(tallies(decoder, over: taps), uniquingKeysWith: +) }
            byBucket["all"] = byBucket.values.reduce(Tally(), +)
            for b in ["fast <0.25s", "medium", "slow >0.45s", "all"] {
                let t = byBucket[b] ?? Tally()
                emit([
                    "mode": "speed", "test": test.name, "decoder": name, "bucket": b, "taps": t.taps,
                    "err_pct": round(100 * t.errorRate, 2), "fixed": t.fixed, "induced": t.induced,
                    "induced_per_1000": round(1000 * Double(t.induced) / Double(max(t.taps, 1)), 2),
                ])
            }
        }
    }
}

func runSweep() {
    let sets = tests.flatMap { test in (0..<seeds).map { speedMix(test.lines, seed: $0) } }
    // Only λσ² decides between two keys, so λ stays put and the sigmas move.
    let tunings = [6.5, 7.5, 8.5, 9.5, 10.5].flatMap { fast in
        [3, 3.5, 4, 4.5, 5, 6].flatMap { slow in
            [0, 0.3, 0.5].map { anchor in
                TapTuning(sigmaFast: fast, sigmaSlow: slow, intervalFast: 0.15, intervalSlow: 0.6, lambda: TapTuning.shipped.lambda, anchor: anchor)
            }
        }
    }
    var rows: [(Double, KeyValuePairs<String, Any>)] = []
    for tuning in tunings {
        var byBucket: [String: Tally] = [:]
        for taps in sets { byBucket.merge(tallies(.decoded(tuning), over: taps), uniquingKeysWith: +) }
        let all = byBucket.values.reduce(Tally(), +), slow = byBucket["slow >0.45s"] ?? Tally()
        rows.append((all.errorRate, [
            "mode": "sweep", "lambda": Double(tuning.lambda), "sigma_fast": Double(tuning.sigmaFast),
            "sigma_slow": Double(tuning.sigmaSlow), "anchor": Double(tuning.anchor), "taps": all.taps,
            "err_pct": round(100 * all.errorRate, 3), "fixed": all.fixed, "induced": all.induced,
            "slow_err_pct": round(100 * slow.errorRate, 3), "slow_induced": slow.induced,
        ]))
    }
    for (_, row) in rows.sorted(by: { $0.0 < $1.0 }) { emit(row) }
}

func runLatency() {
    var rng = SplitMix64(seed: 1)
    let lines = tests.flatMap(\.lines)
    var decode: [UInt64] = [], suggest: [UInt64] = []
    for line in lines {
        let taps = replay.taps(line, rng: &rng) { _ in (0.3, 7) }
        var typed = ""
        for tap in taps {
            guard let tap else {
                typed += " "
                continue
            }
            let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let key = model.key(at: tap.point, in: replay.layout, shifted: tap.shifted, before: typed, interval: tap.interval)
            let decoded = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            typed += replay.text(of: key, shifted: tap.shifted)
            let before = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            _ = model.completions(after: typed)
            let after = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            decode.append(decoded - start)
            suggest.append(after - before)
        }
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: modelPath)[.size] as? Int) ?? -1
    for (name, samples) in [("decode tap", decode), ("completions", suggest)] {
        let sorted = samples.sorted()
        let mean = Double(sorted.reduce(0, +)) / Double(sorted.count)
        emit([
            "mode": "latency", "what": name, "samples": sorted.count, "mean_us": round(mean / 1000, 2),
            "p50_us": round(Double(sorted[sorted.count / 2]) / 1000, 2),
            "p99_us": round(Double(sorted[sorted.count * 99 / 100]) / 1000, 2),
            "max_us": round(Double(sorted.last!) / 1000, 2), "model_bytes": size,
        ])
    }
}

/// Border taps worth trying by hand: the key under the finger is wrong for every point within 1 pt, and the
/// decoder types the intended key there even for a slow, deliberate tap, after a context typed with centre taps.
func runExamples() {
    var rng = SplitMix64(seed: 2)
    var seen = Set<String>()
    var found = 0
    for line in tests.flatMap(\.lines) where found < 12 {
        let scalars = Array(line.unicodeScalars)
        let taps = replay.taps(line, rng: &rng) { _ in (.infinity, 7) }
        for (i, tap) in taps.enumerated() where i <= 16 {
            guard let tap else { continue }
            let context = String(String.UnicodeScalarView(scalars[..<i]))
            let neighbourhood = (-1...1).flatMap { dx in (-1...1).map { dy in CGPoint(x: tap.point.x + CGFloat(dx), y: tap.point.y + CGFloat(dy)) } }
            let robust = neighbourhood.allSatisfy { point in
                let moved = Tap(intended: tap.intended, shifted: tap.shifted, point: point, interval: .infinity)
                return replay.text(of: replay.key(for: moved, after: "", with: .geometric), shifted: tap.shifted) != tap.intended
                    && replay.text(of: replay.key(for: moved, after: context, with: .decoded(.shipped)), shifted: tap.shifted) == tap.intended
            }
            guard robust, i >= 2, !context.hasSuffix(" "), seen.insert(context + tap.intended).inserted else { continue }
            let under = replay.layout.key(at: tap.point)!
            emit([
                "mode": "example", "context": context, "intended": tap.intended, "shift": tap.shifted,
                "touch_x": round(Double(tap.point.x), 1), "touch_y": round(Double(tap.point.y), 1),
                "key_under_finger": replay.text(of: under, shifted: tap.shifted),
                "under_hit_rect": [round(Double(under.hit.minX), 2), round(Double(under.hit.minY), 2), round(Double(under.hit.maxX), 2), round(Double(under.hit.maxY), 2)],
            ])
            found += 1
            break
        }
    }
}

/// A suggestion is right when what tapping it inserts is how the line goes on, so a shorter word that the line
/// continues past still counts; `saved` is the letters the right suggestions would have typed.
func runSuggest() {
    for test in tests {
        var reads = 0, top1 = 0, top3 = 0, saved = 0
        for line in test.lines {
            let scalars = Array(line.unicodeScalars)
            for i in 1..<max(1, scalars.count) where (0x0E01...0x0E5B).contains(scalars[i - 1].value) {
                let typed = String(String.UnicodeScalarView(scalars[..<i]))
                let rest = String(String.UnicodeScalarView(scalars[i...]))
                let offered = model.completions(after: typed)
                guard !offered.isEmpty else { continue }
                reads += 1
                let right = offered.map { rest.unicodeScalars.starts(with: $0.remainder.unicodeScalars) }
                if right.first == true {
                    top1 += 1
                    saved += offered[0].remainder.unicodeScalars.count
                }
                if right.contains(true) { top3 += 1 }
            }
        }
        emit([
            "mode": "suggest", "test": test.name, "reads": reads,
            "top1_pct": round(100 * Double(top1) / Double(max(reads, 1)), 2),
            "top3_pct": round(100 * Double(top3) / Double(max(reads, 1)), 2),
            "top1_saved_letters_per_read": round(Double(saved) / Double(max(reads, 1)), 3),
        ])
    }
}

/// Errors of the shipped decoder alone against the same taps with retyping, and how many lines typed with every
/// tap dead on its key retyping changes at all.
struct RetypeResult {
    var shipped = Tally(), fast = Tally(), slow = Tally(), medium = Tally()
    var cleanLines = 0, cleanChanged: [String: Int] = [:]
    /// What retyping made of clean taps, as the words around each change: typed → retyped.
    var cleanExamples: [String] = []
    var times: [UInt64] = []

    var all: Tally { fast + medium + slow }
}

func measureRetype(_ tuning: RetypeTuning, seeds: Range<Int>, lines: [String]) -> RetypeResult {
    var result = RetypeResult()
    for seed in seeds {
        for taps in speedMix(lines, seed: seed) {
            let shipped = replay.decode(taps, with: .decoded(tuning.tap))
            let retyped = replay.retyped(taps, tuning: tuning, retypeTime: &result.times)
            for (i, tap) in taps.enumerated() {
                guard let tap else { continue }
                result.shipped.add(intended: tap.intended, geometric: tap.intended, decoded: shipped[i])
                switch bucket(tap.interval) {
                case "fast <0.25s": result.fast.add(intended: tap.intended, geometric: shipped[i], decoded: retyped[i])
                case "medium": result.medium.add(intended: tap.intended, geometric: shipped[i], decoded: retyped[i])
                default: result.slow.add(intended: tap.intended, geometric: shipped[i], decoded: retyped[i])
                }
            }
        }
    }
    var rng = SplitMix64(seed: 7)
    var ignored: [UInt64] = []
    for line in lines {
        result.cleanLines += 1
        for interval in [0.1, 0.6] {
            let taps = replay.taps(line, rng: &rng) { _ in (interval, 0) }
            let retyped = replay.retyped(taps, tuning: tuning, retypeTime: &ignored)
            let changed = zip(taps, retyped).enumerated().filter { _, pair in pair.0.map { $0.intended != pair.1 } ?? false }.map(\.offset)
            guard let first = changed.first, let last = changed.last else { continue }
            result.cleanChanged["\(interval)", default: 0] += 1
            let scalars = Array(line.unicodeScalars)
            let around = max(0, first - 8)..<min(scalars.count, last + 6)
            let before = String(String.UnicodeScalarView(scalars[around]))
            let after = retyped[around].joined()
            result.cleanExamples.append("\(interval)s: \(before) → \(after)")
        }
    }
    return result
}

func describe(_ tuning: RetypeTuning) -> String {
    "lambda \(tuning.lambda) slack \(tuning.slack) window \(tuning.window) beam \(tuning.beam) reach \(tuning.reach)"
}

func runRetype() {
    let lines = tests.flatMap(\.lines)
    let r = measureRetype(retypeTuning, seeds: 0..<seeds, lines: lines)
    for (name, t) in [("fast <0.25s", r.fast), ("medium", r.medium), ("slow >0.45s", r.slow), ("all", r.all)] {
        emit([
            "mode": "retype", "tuning": describe(retypeTuning), "bucket": name, "taps": t.taps,
            "err_pct_shipped": round(100 * Double(t.errors - t.induced + t.fixed) / Double(max(t.taps, 1)), 3),
            "err_pct_retype": round(100 * t.errorRate, 3), "fixed": t.fixed, "broken": t.induced,
        ])
    }
    emit(["mode": "retype clean", "tuning": describe(retypeTuning), "lines": r.cleanLines, "changed_fast_0.1s": r.cleanChanged["0.1"] ?? 0,
          "changed_slow_0.6s": r.cleanChanged["0.6"] ?? 0, "examples": r.cleanExamples])
    let sorted = r.times.sorted()
    emit([
        "mode": "retype latency", "samples": sorted.count,
        "mean_us": round(Double(sorted.reduce(0, +)) / Double(sorted.count) / 1000, 2),
        "p50_us": round(Double(sorted[sorted.count / 2]) / 1000, 2),
        "p90_us": round(Double(sorted[sorted.count * 9 / 10]) / 1000, 2),
        "p99_us": round(Double(sorted[sorted.count * 99 / 100]) / 1000, 2),
        "max_us": round(Double(sorted.last!) / 1000, 2),
    ])
}

func runRetypeSweep() {
    let lines = tests.flatMap(\.lines)
    let tunings = [0.3, 0.5, 0.7, 1.0].flatMap { lambda in
        [0, 1, 2, 3, 4].flatMap { slack in
            [4, 6, 8].map { window in RetypeTuning(lambda: Float(lambda), slack: Float(slack), window: window, beam: 16, reach: 45) }
        }
    }
    var results = Array(repeating: RetypeResult(), count: tunings.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: tunings.count) { i in
        var r = measureRetype(tunings[i], seeds: 0..<1, lines: lines)
        r.times = []
        lock.lock()
        results[i] = r
        lock.unlock()
    }
    for (tuning, r) in zip(tunings, results).sorted(by: { $0.1.all.errors < $1.1.all.errors }) {
        let a = r.all
        emit([
            "mode": "retype sweep", "lambda": Double(tuning.lambda), "slack": Double(tuning.slack), "window": tuning.window,
            "err_pct_shipped": round(100 * r.shipped.errorRate, 3), "err_pct_retype": round(100 * a.errorRate, 3),
            "fixed": a.fixed, "broken": a.induced, "broken_per_fixed": round(Double(a.induced) / Double(max(a.fixed, 1)), 3),
            "slow_fixed": r.slow.fixed, "slow_broken": r.slow.induced,
            "clean_changed_fast": r.cleanChanged["0.1"] ?? 0, "clean_changed_slow": r.cleanChanged["0.6"] ?? 0,
        ])
    }
}

switch command {
case "retype": runRetype()
case "retype-sweep": runRetypeSweep()
case "suggest": runSuggest()
case "fixed": runFixed()
case "speed": runSpeed()
case "sweep": runSweep()
case "latency": runLatency()
case "examples": runExamples()
default:
    runFixed()
    runSpeed()
    runLatency()
    runExamples()
}
