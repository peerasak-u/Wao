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
    private var utteranceBegan = Date()

    /// Called on the tap's thread with a 0...1 loudness while capturing.
    var onLevel: (@Sendable (Float) -> Void)?
    /// Called once when an utterance reaches `maxUtteranceSeconds`.
    var onLimit: (@Sendable () -> Void)?

    var isRunning: Bool {
        #if DEBUG
        if fakeMic != nil { return true }
        #endif
        return engine.isRunning
    }

    func start() throws {
        guard !isRunning else { return }
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["WAO_FAKE_MIC"] {
            return try startFakeMic(URL(fileURLWithPath: path))
        }
        #endif
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
        #if DEBUG
        fakeMic?.cancel()
        fakeMic = nil
        #endif
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
            utteranceBegan = Date()
        }
    }

    /// The last `seconds` of the utterance so far; `clipped` when earlier audio was left out.
    func recent(seconds: Double) -> (samples: [Float], clipped: Bool) {
        lock.withLock {
            let window = Int(seconds * Double(MelFeaturizer.sampleRate))
            return (Array(samples.suffix(window)), samples.count > window)
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
        append(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }

    private func append(_ chunk: UnsafeBufferPointer<Float>) {
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

    #if DEBUG
    private var fakeMic: DispatchSourceTimer?

    /// The simulator has no repeatable microphone: `WAO_FAKE_MIC=<16 kHz mono wav>` plays that file from its
    /// start into every utterance at real-time pace, then silence.
    private func startFakeMic(_ url: URL) throws {
        let audio = try AudioFile.load16kMono(url)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.peerasak.wao.fake-mic"))
        var fed = 0
        var utterance = Date.distantPast
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let (live, began) = self.lock.withLock { (self.capturing, self.utteranceBegan) }
            guard live else { return }
            if began != utterance {
                utterance = began
                fed = 0
            }
            let due = Int(Date().timeIntervalSince(began) * Double(MelFeaturizer.sampleRate))
            guard due > fed else { return }
            var chunk = [Float](repeating: 0, count: due - fed)
            if fed < audio.count {
                let end = min(due, audio.count)
                chunk.replaceSubrange(0..<(end - fed), with: audio[fed..<end])
            }
            fed = due
            chunk.withUnsafeBufferPointer { self.append($0) }
        }
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.resume()
        fakeMic = timer
    }
    #endif
}
