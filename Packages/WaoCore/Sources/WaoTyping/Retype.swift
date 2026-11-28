import CoreGraphics
import Foundation

/// A touch on a character key of the Thai letters page, and what it typed.
public struct Touch: Equatable, Sendable {
    public let point: CGPoint
    /// Seconds after the previous character touch; `.infinity` when there was none.
    public let interval: TimeInterval
    /// Shift was on, so the keys around the finger type their shifted letters.
    public let shifted: Bool
    public fileprivate(set) var text: String

    public init(point: CGPoint, interval: TimeInterval, shifted: Bool, text: String) {
        self.point = point
        self.interval = interval
        self.shifted = shifted
        self.text = text
    }
}

/// A change to the end of the text before the cursor: `old` goes and `new` takes its place.
public struct Rewrite: Equatable, Sendable {
    public let old: String
    public let new: String

    public init(old: String, new: String) {
        self.old = old
        self.new = new
    }
}

extension Rewrite {
    /// Makes the rewrite through a keyboard's text proxy, which can only delete backward and insert. How much one
    /// delete takes is the host's call, one scalar of a Thai cluster or the whole cluster, so the text is read back
    /// after each and anything taken past `old` is typed again. False when the text before the cursor did not end
    /// with `old`, the host stopped deleting, or the result does not end with `new`.
    public func apply(before: () -> String, deleteBackward: () -> Void, insert: (String) -> Void) -> Bool {
        let start = Array(before().unicodeScalars)
        let keep = start.count - old.unicodeScalars.count
        guard keep >= 0, start.suffix(from: keep).elementsEqual(old.unicodeScalars) else { return false }
        var now = start
        while now.count > keep {
            deleteBackward()
            let next = Array(before().unicodeScalars)
            guard next.count < now.count, start.starts(with: next) else { break }
            now = next
        }
        if now.count > keep {
            insert(String(String.UnicodeScalarView(start[now.count...])))
            return false
        }
        insert(String(String.UnicodeScalarView(start[now.count..<keep])) + new)
        return before().endsInScalars(new)
    }
}

/// Every tunable of retyping; wao-typing-eval's retype mode measured `shipped`.
public struct RetypeTuning: Equatable, Sendable {
    /// Weight of the language model against the touch positions.
    public var lambda: Float
    /// Nats taken off text for each letter since the last space that no dictionary word explains.
    public var lexicon: Float
    /// How far, in nats, retyped text must outscore what the touches typed to replace it: about 3 to 1 odds.
    public var margin: Float
    /// How many of the latest touches retyping may change.
    public var window: Int
    public var beam: Int
    /// Keys whose cap centre lies this far from the touch, in points, are the ones it may have meant.
    public var reach: CGFloat
    /// Where each touch's spread comes from.
    public var tap: TapTuning

    public init(lambda: Float, lexicon: Float, margin: Float, window: Int, beam: Int, reach: CGFloat, tap: TapTuning = .shipped) {
        self.lambda = lambda
        self.lexicon = lexicon
        self.margin = margin
        self.window = window
        self.beam = beam
        self.reach = reach
        self.tap = tap
    }

    public static let shipped = RetypeTuning(lambda: 0.7, lexicon: 1, margin: 1, window: 8, beam: 8, reach: 45)
}

/// The touches that typed the text right before the cursor since the last space, and the last automatic retype
/// of them, which the next delete undoes. It only holds while the host's text still ends with what they typed.
public struct TouchTrail: Equatable, Sendable {
    public private(set) var touches: [Touch] = []
    /// How many leading touches the user confirmed by undoing a retype; retyping leaves them as they are.
    public private(set) var frozen = 0
    private var undo: Rewrite?

    public init() {}

    public var text: String { touches.map(\.text).joined() }

    /// A touch typed `touch.text` at the end of the trail.
    public mutating func record(_ touch: Touch) {
        undo = nil
        touches.append(touch)
        if touches.count > TypingModel.runLength {
            touches.removeFirst()
            frozen = max(0, frozen - 1)
        }
    }

    public mutating func reset() { self = TouchTrail() }

    /// Forgets the trail when `context`, the text before the cursor, no longer ends with what it typed.
    public mutating func follow(_ context: String) {
        if !context.endsInScalars(text) { reset() }
    }

    /// After a delete: drops the touches whose text the host no longer has before the cursor.
    public mutating func deleted(leaving context: String) {
        undo = nil
        while !touches.isEmpty, !context.endsInScalars(text) { touches.removeLast() }
        frozen = min(frozen, touches.count)
    }

    /// A delete right after an automatic retype: the rewrite back to what the touches typed, which the user
    /// meant after all, so no touch is retyped again.
    public mutating func undoRetype(before context: String) -> Rewrite? {
        guard let undo, context.endsInScalars(text) else { return nil }
        self.undo = nil
        restore(undo.new)
        frozen = touches.count
        return undo
    }

    /// When touches near the latest ones would type text that is clearly likelier, the rewrite to it; the trail
    /// then holds the new text.
    public mutating func retype(before context: String, model: TypingModel, layout: KeyLayout,
                                tuning: RetypeTuning = .shipped) -> Rewrite? {
        guard context.endsInScalars(text) else { return nil }
        let first = max(frozen, touches.count - tuning.window)
        let changing = touches[first...]
        let old = changing.map(\.text).joined()
        let prefix = String(String.UnicodeScalarView(context.unicodeScalars.dropLast(old.unicodeScalars.count)))
        guard let texts = model.retype(changing, after: prefix, in: layout, tuning: tuning) else { return nil }
        let same = zip(changing, texts).prefix { $0.text == $1 }.count
        let rewrite = Rewrite(old: changing.dropFirst(same).map(\.text).joined(), new: texts.dropFirst(same).joined())
        for (i, text) in zip(touches.indices.dropFirst(first), texts) { touches[i].text = text }
        undo = Rewrite(old: rewrite.new, new: rewrite.old)
        return rewrite
    }

    /// Puts `old`, the text the latest touches typed before a retype, back on them.
    private mutating func restore(_ old: String) {
        var rest = Array(old.unicodeScalars)
        for i in touches.indices.reversed() where !rest.isEmpty {
            let count = touches[i].text.unicodeScalars.count
            touches[i].text = String(String.UnicodeScalarView(rest.suffix(count)))
            rest.removeLast(count)
        }
    }
}

extension TypingModel {
    /// What each of `touches` should have typed after `prefix`, when that differs from what they did; `nil`
    /// otherwise. Text is scored as the channel a keyboard is: each touch scores `-½(d/σ)²` for its distance to
    /// the key it types, with σ from its interval, so a slow touch costs about 40 nats to move one key and a
    /// hurried one about 7; the text scores λ·ln P, less `tuning.lexicon` for each letter no dictionary word
    /// explains. The likeliest text replaces the typed one only when it wins by `tuning.margin`.
    func retype(_ touches: ArraySlice<Touch>, after prefix: String, in layout: KeyLayout, tuning: RetypeTuning) -> [String]? {
        let fixed = run(before: prefix)
        let literal = touches.compactMap { id(of: $0.text) }
        guard literal.count == touches.count else { return nil }
        func unexplained(_ ids: some Collection<UInt8>) -> Float {
            tuning.lexicon * Float(WordBreaks(fixed + ids, in: self).open)
        }
        let history = normalized(prefix, keep: order - 1)
        typealias Choice = (id: UInt8, text: String, cost: Float)
        let choices: [[Choice]] = touches.map { touch in
            let sigma = Float(tuning.tap.sigma(after: touch.interval))
            return layout.characterKeys.compactMap { key in
                guard case .character(let character) = key.kind else { return nil }
                let text = character.text(shifted: touch.shifted)
                let dx = Float(touch.point.x - key.cap.midX), dy = Float(touch.point.y - key.cap.midY)
                guard text == touch.text || (dx * dx + dy * dy).squareRoot() <= Float(tuning.reach),
                      let id = id(of: text) else { return nil }
                return (id, text, 0.5 * (dx * dx + dy * dy) / (sigma * sigma))
            }
        }

        var ids = history.ids
        var literalScore: Float = 0
        for (touch, options) in zip(touches, choices) {
            let typed = options.first { $0.text == touch.text }!
            literalScore += tuning.lambda * nextCharacter(after: ids, atLineStart: history.atLineStart).logP(typed.id) - typed.cost
            ids.append(typed.id)
        }

        struct Path { var ids: [UInt8]; var texts: [String]; var score: Float }
        var beam = [Path(ids: history.ids, texts: [], score: 0)]
        for options in choices {
            var next: [Path] = []
            for path in beam {
                let distribution = nextCharacter(after: path.ids, atLineStart: history.atLineStart)
                for option in options {
                    next.append(Path(ids: path.ids + [option.id], texts: path.texts + [option.text],
                                     score: path.score + tuning.lambda * distribution.logP(option.id) - option.cost))
                }
            }
            beam = Array(next.sorted { $0.score > $1.score }.prefix(tuning.beam))
        }
        let typedTexts = touches.map(\.text)
        let rescored = beam.filter { $0.texts != typedTexts }.map { ($0.texts, $0.score - unexplained($0.ids.suffix(touches.count))) }
        guard let best = rescored.max(by: { $0.1 < $1.1 }), best.1 > literalScore - unexplained(literal) + tuning.margin else {
            return nil
        }
        return best.0
    }
}

extension String {
    /// By scalars, not characters: a Thai mark typed on its own joins the character before it.
    func endsInScalars(_ suffix: String) -> Bool {
        unicodeScalars.reversed().starts(with: suffix.unicodeScalars.reversed())
    }
}
