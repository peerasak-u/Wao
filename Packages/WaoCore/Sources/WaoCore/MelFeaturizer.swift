import Accelerate
import Foundation

/// Log-mel features laid out as the encoder's `audio_signal` `[128, frames]`, mel-major.
public struct LogMelFeatures: Sendable {
    public let values: [Float]
    public let frames: Int
    /// Frames at or past this index are padding (zeroed), as NeMo masks them.
    public let validFrames: Int
}

/// NeMo's AudioToMelSpectrogramPreprocessor as the model's config sets it: 16 kHz, n_fft 512,
/// 400-sample symmetric Hann centred in the FFT frame, hop 160, pre-emphasis 0.97, power spectrum,
/// 128 slaney mels over 0-8 kHz, log(x + 2^-24), no normalisation, center=True with zero padding.
/// Computed in Double so it tracks the float64 Python reference.
public struct MelFeaturizer: Sendable {
    public static let sampleRate = 16_000
    public static let melCount = 128
    static let fftSize = 512
    static let windowLength = 400
    static let hop = 160
    static let bins = fftSize / 2 + 1
    static let preemphasis = 0.97
    static let logGuard = pow(2.0, -24.0)

    private let window: [Double]
    private let filterbank: [Double]

    public init() {
        var window = [Double](repeating: 0, count: Self.fftSize)
        let offset = (Self.fftSize - Self.windowLength) / 2
        for n in 0..<Self.windowLength {
            window[offset + n] = 0.5 - 0.5 * cos(2 * Double.pi * Double(n) / Double(Self.windowLength - 1))
        }
        self.window = window
        self.filterbank = Self.slaneyFilterbank()
    }

    public func callAsFunction(_ audio: [Float]) -> LogMelFeatures {
        let pad = Self.fftSize / 2
        var x = [Double](repeating: 0, count: audio.count + 2 * pad)
        if let first = audio.first {
            x[pad] = Double(first)
            for i in 1..<audio.count {
                x[pad + i] = Double(audio[i]) - Self.preemphasis * Double(audio[i - 1])
            }
        }
        let frames = 1 + (x.count - Self.fftSize) / Self.hop
        let bins = Self.bins
        var power = [Double](repeating: 0, count: bins * frames)

        let setup = vDSP_DFT_zrop_CreateSetupD(nil, vDSP_Length(Self.fftSize), .FORWARD)!
        defer { vDSP_DFT_DestroySetupD(setup) }
        let half = Self.fftSize / 2
        var evens = [Double](repeating: 0, count: half), odds = evens
        var re = evens, im = evens
        for t in 0..<frames {
            let start = t * Self.hop
            for i in 0..<half {
                evens[i] = x[start + 2 * i] * window[2 * i]
                odds[i] = x[start + 2 * i + 1] * window[2 * i + 1]
            }
            vDSP_DFT_ExecuteD(setup, evens, odds, &re, &im)
            // zrop packs Nyquist into im[0] and scales every bin by 2.
            power[t] = re[0] * re[0] / 4
            power[(bins - 1) * frames + t] = im[0] * im[0] / 4
            for k in 1..<half {
                power[k * frames + t] = (re[k] * re[k] + im[k] * im[k]) / 4
            }
        }

        var mel = [Double](repeating: 0, count: Self.melCount * frames)
        vDSP_mmulD(filterbank, 1, power, 1, &mel, 1, vDSP_Length(Self.melCount), vDSP_Length(frames), vDSP_Length(bins))

        let valid = audio.count / Self.hop
        var values = [Float](repeating: 0, count: mel.count)
        for m in 0..<Self.melCount {
            for t in 0..<min(valid, frames) {
                values[m * frames + t] = Float(log(mel[m * frames + t] + Self.logGuard))
            }
        }
        return LogMelFeatures(values: values, frames: frames, validFrames: valid)
    }

    /// librosa.filters.mel(sr=16000, n_fft=512, n_mels=128, norm="slaney"), rounded to Float as NeMo stores it.
    static func slaneyFilterbank() -> [Double] {
        let fSp = 200.0 / 3, minLogHz = 1000.0, minLogMel = 1000.0 / (200.0 / 3), logStep = log(6.4) / 27
        func hzToMel(_ f: Double) -> Double { f >= minLogHz ? minLogMel + log(f / minLogHz) / logStep : f / fSp }
        func melToHz(_ m: Double) -> Double { m >= minLogMel ? minLogHz * exp(logStep * (m - minLogMel)) : fSp * m }

        let nyquist = Double(sampleRate) / 2
        let fftFreqs = (0..<bins).map { nyquist * Double($0) / Double(bins - 1) }
        let maxMel = hzToMel(nyquist)
        let melF = (0..<(melCount + 2)).map { melToHz(maxMel * Double($0) / Double(melCount + 1)) }

        var weights = [Double](repeating: 0, count: melCount * bins)
        for i in 0..<melCount {
            let enorm = 2 / (melF[i + 2] - melF[i])
            for k in 0..<bins {
                let lower = (fftFreqs[k] - melF[i]) / (melF[i + 1] - melF[i])
                let upper = (melF[i + 2] - fftFreqs[k]) / (melF[i + 2] - melF[i + 1])
                weights[i * bins + k] = Double(Float(max(0, min(lower, upper)) * enorm))
            }
        }
        return weights
    }
}
