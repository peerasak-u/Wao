import WaoCore
import XCTest

final class ModelStoreTests: XCTestCase {
    func testConvergesToReadyAndNeverRefetchesFinishedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let remote = root.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        let weights = Data(repeating: 1, count: 300_000)
        try weights.write(to: remote.appendingPathComponent("w.data"))
        let entries = ["encoder.int8.onnx": Data("enc".utf8), "tokens.txt": Data("a\nb\n".utf8)]
        for (name, data) in entries { try data.write(to: remote.appendingPathComponent(name)) }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = remote
        zip.arguments = ["-q", "-0", "-X", "m.zip"] + entries.keys.sorted()
        try zip.run()
        zip.waitUntilExit()
        func size(_ name: String) throws -> UInt64 {
            (try FileManager.default.attributesOfItem(atPath: remote.appendingPathComponent(name).path)[.size] as! NSNumber).uint64Value
        }
        let manifest = ModelManifest(
            weights: RemoteFile(name: "w.data", url: remote.appendingPathComponent("w.data"), size: try size("w.data")),
            archive: RemoteFile(name: "m.zip", url: remote.appendingPathComponent("m.zip"), size: try size("m.zip")),
            archiveEntries: entries.mapValues { UInt64($0.count) })
        let local = root.appendingPathComponent("Models/m")
        let store = ModelStore(directory: local, manifest: manifest)

        XCTAssertEqual(store.diskState(), .missing)
        let first = await store.ensureReady()
        XCTAssertEqual(first, .ready(directory: local))
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("m.zip").path))

        try FileManager.default.removeItem(at: remote.appendingPathComponent("w.data"))
        let second = await store.ensureReady()
        XCTAssertEqual(second, .ready(directory: local), "a finished file was fetched again")

        try FileManager.default.removeItem(at: local.appendingPathComponent("tokens.txt"))
        let third = await store.ensureReady()
        XCTAssertEqual(third, .ready(directory: local), "a lost entry should be restored from the archive")
        XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent("tokens.txt")), entries["tokens.txt"])

        try FileManager.default.removeItem(at: remote.appendingPathComponent("m.zip"))
        try FileManager.default.removeItem(at: local.appendingPathComponent("tokens.txt"))
        guard case .failed = await store.ensureReady() else { return XCTFail("missing source should fail") }
        XCTAssertEqual(store.diskState(), .missing)
    }
}
