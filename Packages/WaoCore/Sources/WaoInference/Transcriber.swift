import Foundation
import WaoCore

public struct Transcription: Equatable, Sendable {
    public let text: String
    public let tokens: [Int]
    public let audioSeconds: Double
    public let featureSeconds: Double
    public let encoderSeconds: Double
    public let decoderSeconds: Double

    public var totalSeconds: Double { featureSeconds + encoderSeconds + decoderSeconds }
    public var realTimeFactor: Double { audioSeconds > 0 ? totalSeconds / audioSeconds : 0 }
}

public struct BeamSettings: Sendable {
    public var width: Int
    public var hotwordBonus: Float
    /// Given per emitted piece rather than on the blank: every hypothesis ends each frame with one blank, so a
    /// bias there would cancel out.
    public var blankBias: Float
    /// Fast speech needs more than one piece per 80 ms frame; with one, letters went missing.
    public var symbolsPerFrame: Int
    /// Beam search now and then stops emitting for the rest of an utterance (4 of the 60 tech clips, in Wao and in
    /// PoodPim alike). When its output has fewer pieces than this share of a greedy decode's, the greedy one is
    /// used instead; nil skips the greedy decode.
    public var deletionGuard: Double?

    /// PoodPim's tuning on its tech-podcast set and a user's own voice: beam 6 with a 2.0 bonus per hotword piece
    /// found the most English terms with the fewest wrong Latin words; wider beams or bigger bonuses added more
    /// wrong ones.
    public static let poodPim = BeamSettings(
        width: 6, hotwordBonus: 2.0, blankBias: -0.5, symbolsPerFrame: 3, deletionGuard: 0.8)
}

public enum Decoding: String, Sendable, CaseIterable {
    /// The cheapest; for the live preview.
    case greedy
    /// RNN-T beam search biased towards the hotwords, ported from PoodPim. Falls back to greedy where it doesn't
    /// pay: Thai-only prompt, clips under 2 s, or no hotwords.
    case beam
}

/// OpenThai2.0-ASR-Streaming (int8 ONNX) run whole-utterance on the CPU: log-mel features, the FastConformer
/// encoder with its language prompt, then an RNN-T decode over `decoder_joint.onnx` and the text clean-up.
public final class Transcriber: @unchecked Sendable {
    static let maxSymbolsPerFrame = 2
    static let encoderWidth = 1024
    static let lstmLayers = 2
    static let lstmWidth = 640
    static let lstmShape: [Int64] = [Int64(lstmLayers), 1, Int64(lstmWidth)]

    private let encoder: Session
    private let decoder: Session
    private let vocabulary: Vocabulary
    private let featurizer = MelFeaturizer()
    private let beam: BeamSettings
    private let lexiconLock = NSLock()
    private var lexicon: (hotwords: Hotwords, cleanup: TextCleanup)

    /// On an M4 Mac 2 threads beat 1 by ~20% and 4 add little (TranscriberTests.testThreadCountTiming).
    /// 2 matches the iPhone 15 Pro's two performance cores; the app's test panel can try others.
    public init(
        modelDirectory: URL, threads: Int = 2, hotwords: Hotwords = .bundled, cleanup: TextCleanup = .standard,
        beam: BeamSettings = .poodPim
    ) throws {
        encoder = try Session(path: modelDirectory.appendingPathComponent("encoder.int8.onnx"), threads: threads)
        decoder = try Session(path: modelDirectory.appendingPathComponent("decoder_joint.onnx"), threads: threads)
        vocabulary = try Vocabulary(contentsOf: modelDirectory.appendingPathComponent("tokens.txt"))
        lexicon = (hotwords, cleanup)
        self.beam = beam
    }

    public var hotwords: Hotwords { lexiconLock.withLock { lexicon.hotwords } }

    /// Takes effect from the next `transcribe`; one already running keeps the lists it started with.
    public func use(hotwords: Hotwords, cleanup: TextCleanup) {
        lexiconLock.withLock { lexicon = (hotwords, cleanup) }
    }

    /// `audio` is 16 kHz mono in [-1, 1).
    public func transcribe(_ audio: [Float], language: Language, decoding: Decoding = .beam) throws -> Transcription {
        let (hotwords, cleanup) = lexiconLock.withLock { lexicon }
        let clock = ContinuousClock()
        var t = clock.now
        func lap() -> Double {
            let now = clock.now
            defer { t = now }
            let d = now - t
            return Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
        }

        let features = featurizer(audio)
        let featureSeconds = lap()
        let encoded = try encode(features, language: language)
        let encoderSeconds = lap()
        // The service's "standard" mode: blank bias -1.0, -2.5 for clips under 2 s, and -4.0 if nothing came out.
        let seconds = Double(audio.count) / Double(MelFeaturizer.sampleRate)
        let useBeam = decoding == .beam && language == .thaiEnglishMix && seconds >= 2 && !hotwords.isEmpty
        var tokens = try useBeam ? beamSearch(encoded, hotwords: hotwords) : greedy(encoded, blankBias: seconds < 2 ? -2.5 : -1.0)
        if useBeam, let share = beam.deletionGuard {
            let greedyTokens = try greedy(encoded, blankBias: -1.0)
            if Double(tokens.count) < share * Double(greedyTokens.count) { tokens = greedyTokens }
        }
        if vocabulary.text(for: tokens).isEmpty {
            tokens = try greedy(encoded, blankBias: -4.0)
        }
        let decoderSeconds = lap()
        return Transcription(
            text: cleanup(vocabulary.text(for: tokens)), tokens: tokens, audioSeconds: seconds,
            featureSeconds: featureSeconds, encoderSeconds: encoderSeconds, decoderSeconds: decoderSeconds)
    }

    /// Encoder frames, each `encoderWidth` floats.
    private func encode(_ features: LogMelFeatures, language: Language) throws -> [ArraySlice<Float>] {
        let out = try encoder.run(
            [
                ("audio_signal", Tensor(floats: features.values, shape: [1, Int64(MelFeaturizer.melCount), Int64(features.frames)])),
                ("length", Tensor(int64s: [Int64(features.validFrames)], shape: [1])),
                ("prompt_index", Tensor(int64s: [language.promptIndex], shape: [1])),
            ],
            outputs: ["encoded", "encoded_length"])
        let values = try out[0].elements(Float.self)
        let length = Int(try out[1].elements(Int64.self)[0])
        return (0..<length).map { values[($0 * Self.encoderWidth)..<(($0 + 1) * Self.encoderWidth)] }
    }

    private func greedy(_ frames: [ArraySlice<Float>], blankBias: Double) throws -> [Int] {
        let blank = vocabulary.blankID
        let zeros = [Float](repeating: 0, count: Int(Self.lstmShape.reduce(1, *)))
        var state1 = zeros, state2 = zeros
        var last = blank
        var tokens: [Int] = []
        for frame in frames {
            let encoderFrame = try Tensor(floats: Array(frame), shape: [1, Int64(Self.encoderWidth), 1])
            for _ in 0..<Self.maxSymbolsPerFrame {
                let out = try decoder.run(
                    [
                        ("encoder_outputs", encoderFrame),
                        ("targets", Tensor(int32s: [Int32(last)], shape: [1, 1])),
                        ("target_length", Tensor(int32s: [1], shape: [1])),
                        ("input_states_1", Tensor(floats: state1, shape: Self.lstmShape)),
                        ("input_states_2", Tensor(floats: state2, shape: Self.lstmShape)),
                    ],
                    outputs: ["outputs", "output_states_1", "output_states_2"])
                let scores = try out[0].elements(Float.self)
                var best = 0
                for k in 1..<blank where scores[k] > scores[best] { best = k }
                if Double(scores[blank]) + blankBias > Double(scores[best]) { break }
                tokens.append(best)
                last = best
                state1 = try out[1].elements(Float.self)
                state2 = try out[2].elements(Float.self)
            }
        }
        return tokens
    }

    struct Hypothesis {
        var tokens: [Int]
        var last: Int
        var state1: [Float]
        var state2: [Float]
        var score: Float
        var match: Hotwords.State
    }

    /// Hypotheses with the same pieces are one, their scores log-added; keeps the best `width`.
    static func mergeAndPrune(_ hyps: [Hypothesis], width: Int) -> [Hypothesis] {
        var out: [Hypothesis] = []
        for h in hyps.enumerated().sorted(by: { ($0.element.score, $1.offset) > ($1.element.score, $0.offset) }).map(\.element) {
            if let m = out.firstIndex(where: { $0.tokens == h.tokens }) {
                let (a, c) = (max(out[m].score, h.score), min(out[m].score, h.score))
                out[m].score = a + log(1 + exp(c - a))
            } else if out.count < width {
                out.append(h)
            }
        }
        return out
    }

    /// Every hypothesis ends each frame with one blank, so it may emit up to `symbolsPerFrame` pieces first,
    /// but only while it can still make the beam.
    private func beamSearch(_ frames: [ArraySlice<Float>], hotwords: Hotwords) throws -> [Int] {
        let zeros = [Float](repeating: 0, count: Self.lstmLayers * Self.lstmWidth)
        var hyps = [Hypothesis(tokens: [], last: vocabulary.blankID, state1: zeros, state2: zeros, score: 0, match: .init())]
        for frame in frames {
            var ended: [Hypothesis] = []
            var active = hyps
            for step in 0..<beam.symbolsPerFrame where !active.isEmpty {
                let (stayed, emitted) = try expand(frame, active, hotwords: hotwords)
                ended = Self.mergeAndPrune(ended + stayed, width: beam.width)
                let floor = ended.count >= beam.width ? ended[beam.width - 1].score : -.infinity
                active = Self.mergeAndPrune(emitted.filter { $0.score > floor }, width: beam.width)
                if step + 1 == beam.symbolsPerFrame {
                    ended += active
                }
            }
            hyps = Self.mergeAndPrune(ended, width: beam.width)
        }
        // An unfinished hotword match doesn't count. Ties go to the later one, as Rust's max_by does.
        var best: Hypothesis?
        for h in hyps where best.map({ h.score - h.match.pending >= $0.score - $0.match.pending }) ?? true {
            best = h
        }
        return best?.tokens ?? []
    }

    /// One batched decoder call for all `hyps` on `frame`. Per hypothesis: the blank extension (same state), and
    /// the `width` best pieces (new state). Scores are log-softmax.
    private func expand(_ frame: ArraySlice<Float>, _ hyps: [Hypothesis], hotwords: Hotwords) throws -> (stayed: [Hypothesis], emitted: [Hypothesis]) {
        let b = hyps.count
        let width = Self.lstmWidth
        let blank = vocabulary.blankID
        let classes = blank + 1
        func pack(_ state: KeyPath<Hypothesis, [Float]>) -> [Float] {
            var v: [Float] = []
            v.reserveCapacity(Self.lstmLayers * b * width)
            for layer in 0..<Self.lstmLayers {
                for h in hyps { v += h[keyPath: state][(layer * width)..<((layer + 1) * width)] }
            }
            return v
        }
        let stateShape: [Int64] = [Int64(Self.lstmLayers), Int64(b), Int64(width)]
        let out = try decoder.run(
            [
                ("encoder_outputs", Tensor(floats: Array(repeatElement(frame, count: b).joined()), shape: [Int64(b), Int64(Self.encoderWidth), 1])),
                ("targets", Tensor(int32s: hyps.map { Int32($0.last) }, shape: [Int64(b), 1])),
                ("target_length", Tensor(int32s: [Int32](repeating: 1, count: b), shape: [Int64(b)])),
                ("input_states_1", Tensor(floats: pack(\.state1), shape: stateShape)),
                ("input_states_2", Tensor(floats: pack(\.state2), shape: stateShape)),
            ],
            outputs: ["outputs", "output_states_1", "output_states_2"])
        let scores = try out[0].elements(Float.self)
        let o1 = try out[1].elements(Float.self)
        let o2 = try out[2].elements(Float.self)
        func unpack(_ o: [Float], _ i: Int) -> [Float] {
            var v: [Float] = []
            for layer in 0..<Self.lstmLayers {
                let start = (layer * b + i) * width
                v += o[start..<(start + width)]
            }
            return v
        }
        var stayed: [Hypothesis] = []
        var emitted: [Hypothesis] = []
        for (i, h) in hyps.enumerated() {
            let logits = scores[(i * classes)..<((i + 1) * classes)]
            let top = logits.max()!
            let lse = top + log(logits.reduce(0) { $0 + exp($1 - top) })
            var stay = h
            stay.score += logits[logits.startIndex + blank] - lse
            stayed.append(stay)
            var best: [(piece: Int, score: Float)] = []
            for k in 0..<blank {
                let v = logits[logits.startIndex + k]
                guard best.count < beam.width || v > best[best.count - 1].score else { continue }
                best.insert((k, v), at: best.firstIndex { v > $0.score } ?? best.count)
                if best.count > beam.width { best.removeLast() }
            }
            let (n1, n2) = (unpack(o1, i), unpack(o2, i))
            for (k, v) in best {
                let (match, delta) = hotwords.advance(h.match, piece: vocabulary.pieces[k], bonus: beam.hotwordBonus)
                emitted.append(Hypothesis(
                    tokens: h.tokens + [k], last: k, state1: n1, state2: n2,
                    score: h.score + v - lse - beam.blankBias + delta, match: match))
            }
        }
        return (stayed, emitted)
    }
}
