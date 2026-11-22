import CoreGraphics
import Foundation
import WaoCore

/// Seeded so every run of the eval, and the regression test, sees the same taps.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func gaussian() -> Double {
        let u = Double.random(in: Double.ulpOfOne..<1, using: &self), v = Double.random(in: 0..<1, using: &self)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}

/// One simulated touch: the character meant, where the finger landed, and how long after the previous touch.
struct Tap {
    let intended: String
    let shifted: Bool
    let point: CGPoint
    let interval: TimeInterval
}

enum Decoder {
    case geometric
    case decoded(TapTuning)
}

/// Replays held-out Thai lines as noisy taps on the shipped key grid and decodes them with the shipped code.
struct Replay {
    let layout = KeyLayout(size: CGSize(width: 390, height: 242), rows: Typing().rows)
    let model: TypingModel
    private let keyFor: [String: (PlacedKey, Bool)]

    init(model: TypingModel) {
        self.model = model
        var keyFor: [String: (PlacedKey, Bool)] = [:]
        for key in layout.characterKeys {
            guard case .character(let k) = key.kind else { continue }
            keyFor[k.output] = keyFor[k.output] ?? (key, false)
            keyFor[k.shifted] = keyFor[k.shifted] ?? (key, true)
        }
        self.keyFor = keyFor
    }

    /// Taps for each character of `line`, `nil` for a space, which the eval does not perturb (as the simulation).
    /// `touch` gives each tap's interval and the spread of the finger around the cap centre.
    func taps(_ line: String, rng: inout SplitMix64, touch: (inout SplitMix64) -> (interval: TimeInterval, sigma: Double)) -> [Tap?] {
        line.unicodeScalars.map { scalar in
            let c = String(scalar)
            guard let (key, shifted) = keyFor[c] else { return nil }
            let (interval, sigma) = touch(&rng)
            let x = min(390 - 1e-6, max(0, key.cap.midX + sigma * rng.gaussian()))
            let y = min(layout.characterArea.maxY - 1e-6, max(0, key.cap.midY + sigma * rng.gaussian()))
            return Tap(intended: c, shifted: shifted, point: CGPoint(x: x, y: y), interval: interval)
        }
    }

    /// What each tap typed, each decision seeing only what this decoder itself typed before it on the line.
    func decode(_ taps: [Tap?], with decoder: Decoder) -> [String] {
        var typed = ""
        return taps.map { tap in
            guard let tap else {
                typed += " "
                return " "
            }
            let out = text(of: key(for: tap, after: typed, with: decoder), shifted: tap.shifted)
            typed += out
            return out
        }
    }

    func key(for tap: Tap, after typed: String, with decoder: Decoder) -> PlacedKey? {
        switch decoder {
        case .geometric: layout.key(at: tap.point)
        case .decoded(let tuning): model.key(at: tap.point, in: layout, shifted: tap.shifted, before: typed, interval: tap.interval, tuning: tuning)
        }
    }

    func text(of key: PlacedKey?, shifted: Bool) -> String {
        switch key?.kind {
        case .character(let k): k.text(shifted: shifted)
        case .shift: "<shift>"
        case .delete: "<delete>"
        case nil: "<none>"
        }
    }
}

/// Errors against the truth, and against the geometric keyboard: `fixed` it got wrong and the decoder right,
/// `induced` the other way round.
struct Tally {
    var taps = 0, errors = 0, fixed = 0, induced = 0

    mutating func add(intended: String, geometric: String, decoded: String) {
        taps += 1
        if decoded != intended { errors += 1 }
        if geometric != intended, decoded == intended { fixed += 1 }
        if geometric == intended, decoded != intended { induced += 1 }
    }

    static func + (a: Tally, b: Tally) -> Tally {
        Tally(taps: a.taps + b.taps, errors: a.errors + b.errors, fixed: a.fixed + b.fixed, induced: a.induced + b.induced)
    }

    var errorRate: Double { taps == 0 ? 0 : Double(errors) / Double(taps) }
}

extension TapTuning {
    /// A decoder that ignores tap timing, as the research simulation's.
    static func fixed(sigma: CGFloat, lambda: Float, anchor: CGFloat = 0) -> TapTuning {
        TapTuning(sigmaFast: sigma, sigmaSlow: sigma, intervalFast: 0.15, intervalSlow: 0.6, lambda: lambda, anchor: anchor)
    }
}
