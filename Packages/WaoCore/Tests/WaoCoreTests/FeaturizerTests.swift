import WaoCore
import XCTest

final class FeaturizerTests: XCTestCase {
    /// Tolerance on log-mel values against the float64 Python reference (tools/reference_transcribe.py).
    static let tolerance: Float = 1e-3

    func testFeaturesMatchPythonReference() throws {
        let featurizer = MelFeaturizer()
        let fixtures = try ReferenceFixture.all()
        XCTAssertFalse(fixtures.isEmpty)
        for (name, fixture) in fixtures {
            let audio = try AudioFile.load16kMono(Paths.samples.appendingPathComponent(fixture.wav))
            let features = featurizer(audio)
            XCTAssertEqual(features.frames, fixture.frames, name)
            XCTAssertEqual(features.validFrames, fixture.valid, name)
            let reference = try fixture.mel(named: name)
            XCTAssertEqual(reference.count, features.values.count, name)
            var maxDiff: Float = 0
            for i in reference.indices { maxDiff = max(maxDiff, abs(reference[i] - features.values[i])) }
            print("features \(name): \(fixture.frames) frames, max |swift - python| = \(maxDiff)")
            XCTAssertLessThan(maxDiff, Self.tolerance, name)
        }
    }
}
