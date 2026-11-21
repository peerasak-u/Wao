import Foundation
import XCTest

enum Paths {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let samples = repo.appendingPathComponent("samples")
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    /// The int8 model, from `WAO_MODEL_DIR` or `.model-cache/int8`; tests that need it skip when absent.
    static func modelDirectory() throws -> URL {
        let url = ProcessInfo.processInfo.environment["WAO_MODEL_DIR"].map { URL(fileURLWithPath: $0) }
            ?? repo.appendingPathComponent(".model-cache/int8")
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("encoder.int8.onnx.data").path) else {
            throw XCTSkip("no model at \(url.path); download it to run this test")
        }
        return url
    }
}

struct ReferenceFixture: Decodable {
    let wav: String
    let lang: String
    let frames: Int
    let valid: Int
    let tokens: [Int]
    let text: String

    static func all() throws -> [(name: String, fixture: ReferenceFixture)] {
        try FileManager.default.contentsOfDirectory(atPath: Paths.fixtures.path)
            .filter { $0.hasSuffix(".json") }.sorted()
            .map { name in
                let data = try Data(contentsOf: Paths.fixtures.appendingPathComponent(name))
                return (String(name.dropLast(".json".count)), try JSONDecoder().decode(ReferenceFixture.self, from: data))
            }
    }

    func mel(named name: String) throws -> [Float] {
        let data = try Data(contentsOf: Paths.fixtures.appendingPathComponent("\(name).mel.f32"))
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
