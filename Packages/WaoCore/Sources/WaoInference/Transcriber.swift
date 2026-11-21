import Foundation
import WaoCore

public struct Transcription: Sendable {
    public let text: String
    public let tokens: [Int]
    public let audioSeconds: Double
    public let featureSeconds: Double
    public let encoderSeconds: Double
    public let decoderSeconds: Double

    public var totalSeconds: Double { featureSeconds + encoderSeconds + decoderSeconds }
    public var realTimeFactor: Double { audioSeconds > 0 ? totalSeconds / audioSeconds : 0 }
}

/// OpenThai2.0-ASR-Streaming (int8 ONNX) run whole-utterance on the CPU: log-mel features, the FastConformer
/// encoder with its language prompt, then NeMo's greedy RNN-T loop over `decoder_joint.onnx`.
public final class Transcriber: @unchecked Sendable {
    static let maxSymbolsPerFrame = 2
    static let encoderWidth = 1024
    static let lstmShape: [Int64] = [2, 1, 640]

    private let encoder: Session
    private let decoder: Session
    private let vocabulary: Vocabulary
    private let featurizer = MelFeaturizer()

    /// On an M4 Mac 2 threads beat 1 by ~20% and 4 add little (TranscriberTests.testThreadCountTiming).
    /// 2 matches the iPhone 15 Pro's two performance cores; the app's test panel can try others.
    public init(modelDirectory: URL, threads: Int = 2) throws {
        encoder = try Session(path: modelDirectory.appendingPathComponent("encoder.int8.onnx"), threads: threads)
        decoder = try Session(path: modelDirectory.appendingPathComponent("decoder_joint.onnx"), threads: threads)
        vocabulary = try Vocabulary(contentsOf: modelDirectory.appendingPathComponent("tokens.txt"))
    }

    /// `audio` is 16 kHz mono in [-1, 1).
    public func transcribe(_ audio: [Float], language: Language) throws -> Transcription {
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
        var tokens = try greedy(encoded, blankBias: seconds < 2 ? -2.5 : -1.0)
        if vocabulary.text(for: tokens).isEmpty {
            tokens = try greedy(encoded, blankBias: -4.0)
        }
        let decoderSeconds = lap()
        return Transcription(
            text: vocabulary.text(for: tokens), tokens: tokens, audioSeconds: seconds,
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
}
