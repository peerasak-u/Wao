import AVFoundation
import WaoCore

/// Holds the microphone open for the whole session so recording can start while the app is in the background.
/// Buffers are converted to 16 kHz mono and kept only between `beginUtterance` and `endUtterance`.
final class AudioCapture: @unchecked Sendable {
    static let maxUtteranceSeconds = 120

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var capturing = false
    private var limitReported = false

    /// Called on the tap's thread with a 0...1 loudness while capturing.
    var onLevel: (@Sendable (Float) -> Void)?
    /// Called once when an utterance reaches `maxUtteranceSeconds`.
    var onLimit: (@Sendable () -> Void)?

    var isRunning: Bool { engine.isRunning }

    func start() throws {
        guard !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "No microphone input"])
        }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(MelFeaturizer.sampleRate), channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: inputFormat, to: target)!
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.receive(buffer, converter: converter, target: target)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        _ = endUtterance()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func beginUtterance() {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            limitReported = false
            capturing = true
        }
    }

    func endUtterance() -> [Float] {
        lock.withLock {
            capturing = false
            defer { samples = [] }
            return samples
        }
    }

    private func receive(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat) {
        guard lock.withLock({ capturing }) else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return }
        let chunk = UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))

        var sum: Float = 0
        for x in chunk { sum += x * x }
        let rms = (sum / Float(chunk.count)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-6))
        onLevel?(min(max((decibels + 50) / 45, 0), 1))

        let hitLimit: Bool = lock.withLock {
            guard capturing else { return false }
            samples.append(contentsOf: chunk)
            guard samples.count >= Self.maxUtteranceSeconds * MelFeaturizer.sampleRate, !limitReported else { return false }
            limitReported = true
            return true
        }
        if hitLimit { onLimit?() }
    }
}
