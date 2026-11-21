import WaoCore
import WaoInference
import XCTest

final class TranscriberTests: XCTestCase {
    func testTokensMatchPythonReference() throws {
        let transcriber = try Transcriber(modelDirectory: try Paths.modelDirectory())
        for (name, fixture) in try ReferenceFixture.all() {
            let audio = try AudioFile.load16kMono(Paths.samples.appendingPathComponent(fixture.wav))
            let language = try XCTUnwrap(Language(rawValue: fixture.lang))
            let result = try transcriber.transcribe(audio, language: language, decoding: .greedy)
            print(String(format: "transcribe %@: \"%@\" audio %.2fs, features %.3fs, encoder %.3fs, decoder %.3fs, RTF %.3f (Mac)",
                         name, result.text, result.audioSeconds, result.featureSeconds, result.encoderSeconds,
                         result.decoderSeconds, result.realTimeFactor))
            XCTAssertEqual(result.tokens, fixture.tokens, name)
            XCTAssertEqual(result.text, fixture.text, name)
        }
    }

    func testThreadCountTiming() throws {
        guard ProcessInfo.processInfo.environment["WAO_TIMING"] != nil else { throw XCTSkip("set WAO_TIMING=1") }
        let audio = try AudioFile.load16kMono(Paths.samples.appendingPathComponent("food.wav"))
        for threads in [1, 2, 4] {
            let transcriber = try Transcriber(modelDirectory: try Paths.modelDirectory(), threads: threads)
            _ = try transcriber.transcribe(audio, language: .thai)
            let runs = try (0..<3).map { _ in try transcriber.transcribe(audio, language: .thai).totalSeconds }
            print(String(format: "threads %d: %@ s for %.2f s of audio (Mac)", threads,
                         runs.map { String(format: "%.3f", $0) }.joined(separator: " "), Double(audio.count) / 16_000))
        }
    }
}
