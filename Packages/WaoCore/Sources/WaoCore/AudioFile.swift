import AVFoundation

public enum AudioFile {
    /// Reads a 16 kHz mono file as Float samples in [-1, 1), the scaling soundfile uses for 16-bit PCM.
    public static func load16kMono(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == Double(MelFeaturizer.sampleRate), file.processingFormat.channelCount == 1 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) is not 16 kHz mono"])
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
