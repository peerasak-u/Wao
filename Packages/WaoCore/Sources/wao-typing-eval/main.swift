import CoreGraphics
import Foundation
import WaoCore

let usage = """
    wao-typing-eval [fixed|speed|sweep|latency|examples|all] [--model FILE] [--seeds N] [--sigma PT...]

    Replays the held-out lines in Tests/WaoCoreTests/Fixtures as noisy taps on a 390 x 242 pt Kedmanee grid and
    prints JSON lines comparing the geometric keyboard with tap decoders:
      fixed     fixed touch noise (--sigma, default 7), the research simulation's decoder table
      speed     noise that grows with typing speed, per speed bucket: fixed-sigma decoders against TapTuning.shipped
      sweep     the speed mix over a grid of tunings, best first
      latency   time per decoded tap and per suggestion lookup
      examples  taps that land on the wrong key and come out right even when typed slowly
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
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    func value<T>(_ parse: (String) -> T?) -> T {
        guard let v = args.popFirst().flatMap(parse) else { fail("\(arg) needs a valid value") }
        return v
    }
    switch arg {
    case "--model": modelPath = value { $0 }
    case "--seeds": seeds = value { Int($0) }
    case "--sigma":
        sigmas = []
        while let next = args.first, let value = Double(next) {
            sigmas.append(CGFloat(value))
            args.removeFirst()
        }
    case "fixed", "speed", "sweep", "latency", "examples", "all": command = arg
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

switch command {
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
