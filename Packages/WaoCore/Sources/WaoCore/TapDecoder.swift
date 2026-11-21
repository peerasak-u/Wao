import CoreGraphics
import Foundation

/// Every tunable of tap decoding. `shipped` is the one the keyboard uses; wao-typing-eval measured it.
public struct TapTuning: Equatable, Sendable {
    /// Touch spread in points for taps at most `intervalFast` seconds after the previous one.
    public var sigmaFast: CGFloat
    /// Touch spread for taps at least `intervalSlow` seconds after the previous one, or with none before.
    public var sigmaSlow: CGFloat
    public var intervalFast: TimeInterval
    public var intervalSlow: TimeInterval
    /// Weight of the language model against the touch position.
    public var lambda: Float
    /// Fraction of each cap, centred, where the key under the finger always wins.
    public var anchor: CGFloat

    public init(sigmaFast: CGFloat, sigmaSlow: CGFloat, intervalFast: TimeInterval, intervalSlow: TimeInterval, lambda: Float, anchor: CGFloat) {
        self.sigmaFast = sigmaFast
        self.sigmaSlow = sigmaSlow
        self.intervalFast = intervalFast
        self.intervalSlow = intervalSlow
        self.lambda = lambda
        self.anchor = anchor
    }

    public static let shipped = TapTuning(sigmaFast: 7.5, sigmaSlow: 4, intervalFast: 0.15, intervalSlow: 0.6, lambda: 0.5, anchor: 0.5)

    /// Hurried fingers land further from the key they meant, so the touch counts for less and the context for more;
    /// a deliberate tap is taken nearly at its word.
    public func sigma(after interval: TimeInterval) -> CGFloat {
        let t = (interval - intervalFast) / (intervalSlow - intervalFast)
        return sigmaFast + (sigmaSlow - sigmaFast) * CGFloat(min(1, max(0, t)))
    }
}

/// Which key a touch meant: the most likely key given where the finger landed and what came before.
public enum TapDecoder {
    /// Scores each candidate by `-½(d/σ)² + λ·logPrior`, `d` the distance to its cap centre. A touch on shift or
    /// delete, or in the hit key's anchor, is taken as it is.
    public static func pick(_ point: CGPoint, among candidates: [PlacedKey], hit: PlacedKey?, sigma: CGFloat,
                            tuning: TapTuning, logPrior: (PlacedKey) -> Float) -> PlacedKey? {
        if let hit {
            guard case .character = hit.kind else { return hit }
            if hit.anchor(tuning.anchor).contains(point) { return hit }
        }
        var best: PlacedKey?
        var bestScore = -Float.infinity
        for key in candidates {
            let dx = Float((point.x - key.cap.midX) / sigma), dy = Float((point.y - key.cap.midY) / sigma)
            let score = -0.5 * (dx * dx + dy * dy) + (tuning.lambda > 0 ? tuning.lambda * logPrior(key) : 0)
            if best == nil || score > bestScore {
                best = key
                bestScore = score
            }
        }
        return best
    }
}

extension TypingModel {
    /// The key a touch types on the Thai letters page, `interval` seconds after the previous character touch
    /// (`.infinity` when there was none), with `context` the text before the cursor.
    public func key(at point: CGPoint, in layout: KeyLayout, shifted: Bool, before context: some StringProtocol,
                    interval: TimeInterval, tuning: TapTuning = .shipped) -> PlacedKey? {
        let next = nextCharacter(after: context)
        return TapDecoder.pick(point, among: layout.characterKeys, hit: layout.key(at: point),
                               sigma: tuning.sigma(after: interval), tuning: tuning) {
            guard case .character(let key) = $0.kind else { return -.infinity }
            return next.logP(key.text(shifted: shifted))
        }
    }
}
