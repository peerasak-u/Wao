import WaoCore
import XCTest

final class BridgeTests: XCTestCase {
    var bridge: Bridge!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        bridge = Bridge(directory: dir)
    }

    func testEveryStateRoundTrips() throws {
        let id = UUID()
        let states: [SessionState] = [
            .off, .idle(expiresAt: Date(timeIntervalSince1970: 1_800_000_000)),
            .listening(id: id, language: .thai), .listening(id: id, language: .thaiEnglishMix),
            .transcribing(id: id), .done(id: id, text: "สวัสดีครับ"), .failed(id: id, reason: "no model"),
        ]
        for state in states {
            try bridge.write(state)
            XCTAssertEqual(try bridge.readState(), state)
        }
    }

    func testEveryCommandRoundTrips() throws {
        for kind: Command.Kind in [.start(.thai), .start(.thaiEnglishMix), .stop, .cancel] {
            let command = Command(kind: kind, issuedAt: Date(timeIntervalSince1970: 1_800_000_000))
            try bridge.write(command)
            XCTAssertEqual(try bridge.readCommand(), command)
        }
    }

    func testMissingFilesReadAsNothingYet() throws {
        XCTAssertEqual(try bridge.readState(), .off)
        XCTAssertNil(try bridge.readCommand())
        XCTAssertEqual(bridge.readLevel(), 0)
    }

    func testMalformedStateIsAnErrorNotADefault() throws {
        try Data(#"{"listening":{"id":"not-a-uuid"}}"#.utf8).write(to: bridge.directory.appendingPathComponent("state.json"))
        XCTAssertThrowsError(try bridge.readState()) { error in
            guard case BridgeError.malformed(let file, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(file, "state.json")
        }
    }

    func testLevelRoundTrips() {
        bridge.writeLevel(0.625)
        XCTAssertEqual(bridge.readLevel(), 0.625)
    }
}
