import WaoCore
import XCTest

final class StoredZipTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func zip(_ files: [String: Data], level: String = "-0") throws -> URL {
        for (name, data) in files { try data.write(to: dir.appendingPathComponent(name)) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = dir
        process.arguments = ["-q", level, "-X", "archive.zip"] + files.keys.sorted()
        try process.run()
        process.waitUntilExit()
        for name in files.keys { try FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
        return dir.appendingPathComponent("archive.zip")
    }

    func testExtractsStoredEntries() throws {
        let files = ["a.txt": Data("สวัสดี\n".utf8), "b.bin": Data((0..<100_000).map { UInt8($0 % 251) })]
        let archive = try StoredZip(url: try zip(files))
        XCTAssertEqual(Set(archive.entries.map(\.name)), Set(files.keys))
        for (name, data) in files {
            let out = dir.appendingPathComponent("out-" + name)
            try archive.extract(try XCTUnwrap(archive.entry(named: name)), to: out)
            XCTAssertEqual(try Data(contentsOf: out), data)
        }
    }

    func testCorruptEntryIsRejectedAndLeavesNoFile() throws {
        let url = try zip(["a.bin": Data(repeating: 7, count: 4096)])
        var bytes = try Data(contentsOf: url)
        bytes[100] ^= 0xFF
        try bytes.write(to: url)
        let archive = try StoredZip(url: url)
        let out = dir.appendingPathComponent("out.bin")
        XCTAssertThrowsError(try archive.extract(archive.entries[0], to: out)) {
            XCTAssertEqual($0 as? StoredZipError, .crcMismatch("a.bin"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testCompressedZipIsUnsupported() throws {
        let url = try zip(["a.txt": Data(repeating: 65, count: 10_000)], level: "-9")
        XCTAssertThrowsError(try StoredZip(url: url)) {
            guard case StoredZipError.unsupported = $0 else { return XCTFail("\($0)") }
        }
    }

    func testNotAZip() throws {
        let url = dir.appendingPathComponent("x.zip")
        try Data("hello".utf8).write(to: url)
        XCTAssertThrowsError(try StoredZip(url: url)) { XCTAssertEqual($0 as? StoredZipError, .notAZip) }
    }

    func testReadsTheModelArchive() throws {
        let url = try Paths.modelDirectory().appendingPathComponent("openthai2.0-asr-streaming-int8.asr.zip")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("archive not kept") }
        let archive = try StoredZip(url: url)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: archive.entries.map { ($0.name, $0.size) }),
                       ModelManifest.openThaiInt8.archiveEntries)
        let out = dir.appendingPathComponent("tokens.txt")
        try archive.extract(try XCTUnwrap(archive.entry(named: "tokens.txt")), to: out)
        XCTAssertEqual(try Vocabulary(contentsOf: out).blankID, 14_988)
    }
}
