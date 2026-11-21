import WaoCore
@testable import WaoInference
import XCTest

final class BeamSearchTests: XCTestCase {
    func hyp(_ tokens: [Int], _ score: Float) -> Transcriber.Hypothesis {
        .init(tokens: tokens, last: tokens.last ?? 0, state1: [], state2: [], score: score, match: .init())
    }

    func testSameTokensMergeByLogAdd() {
        let merged = Transcriber.mergeAndPrune([hyp([1], log(0.25)), hyp([2], log(0.4)), hyp([1], log(0.25))], width: 6)
        XCTAssertEqual(merged.map(\.tokens), [[2], [1]], "ordered by score before merging, as PoodPim does")
        XCTAssertEqual(merged[1].score, log(0.5), accuracy: 1e-6)
    }

    func testKeepsTheBestBeamWidthBestFirst() {
        let merged = Transcriber.mergeAndPrune((0..<10).map { hyp([$0], Float($0)) }, width: 6)
        XCTAssertEqual(merged.map { $0.tokens[0] }, [9, 8, 7, 6, 5, 4])
    }

    func testBeamKeepsThaiSpeechThai() throws {
        let transcriber = try Transcriber(modelDirectory: try Paths.modelDirectory())
        for (name, fixture) in try ReferenceFixture.all() {
            let audio = try AudioFile.load16kMono(Paths.samples.appendingPathComponent(fixture.wav))
            let text = try transcriber.transcribe(audio, language: .thaiEnglishMix, decoding: .beam).text
            XCTAssertNil(text.range(of: "[A-Za-z]", options: .regularExpression), "\(name): \(text)")
        }
    }
}
