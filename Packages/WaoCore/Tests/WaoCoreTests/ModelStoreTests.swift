import WaoCore
import XCTest

final class ModelStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testConvergesToReadyAndNeverRefetchesFinishedFiles() async throws {
        let remote = root.appendingPathComponent("remote")
        let (manifest, entries) = try makeModel(in: remote, weights: Data(repeating: 1, count: 300_000)) {
            remote.appendingPathComponent($0)
        }
        let local = root.appendingPathComponent("Models/m")
        let store = ModelStore(directory: local, manifest: manifest)

        XCTAssertEqual(store.state(), .missing)
        let first = await run(ModelDownloader(store: store, configuration: .ephemeral))
        XCTAssertEqual(first, .ready(directory: local))
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("m.zip").path))

        try FileManager.default.removeItem(at: remote.appendingPathComponent("w.data"))
        let second = await run(ModelDownloader(store: store, configuration: .ephemeral))
        XCTAssertEqual(second, .ready(directory: local), "a finished file was fetched again")

        try FileManager.default.removeItem(at: local.appendingPathComponent("tokens.txt"))
        let third = await run(ModelDownloader(store: store, configuration: .ephemeral))
        XCTAssertEqual(third, .ready(directory: local), "a lost entry should be restored from the archive")
        XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent("tokens.txt")), entries["tokens.txt"])

        try FileManager.default.removeItem(at: remote.appendingPathComponent("m.zip"))
        try FileManager.default.removeItem(at: local.appendingPathComponent("tokens.txt"))
        guard case .failed = await run(ModelDownloader(store: store, configuration: .ephemeral)) else {
            return XCTFail("missing source should fail")
        }
        XCTAssertFalse(store.isReady)
    }

    func testPausedDownloadResumesFromResumeDataAfterRelaunch() async throws {
        let weights = randomData(4 << 20)
        let (server, store) = try serve(weights: weights, expiresIn: 3600)

        let kept = try await pauseMidway(store)
        let relaunched = ModelDownloader(store: store, configuration: .ephemeral)
        guard case .paused(let progress) = await next(relaunched) else { return XCTFail("a relaunch should show it paused") }
        XCTAssertEqual(progress.received, kept + store.manifest.archive.size, "paused progress is derived from disk")

        let before = server.requests.count
        let state = await run(relaunched)
        XCTAssertEqual(state, .ready(directory: store.directory))
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("w.data")), weights)
        let resumed = server.requests[before...].filter { $0.path == "/cdn/w.data" }
        XCTAssertEqual(resumed.map(\.rangeStart), [kept], "resume data continues at the byte it stopped")
    }

    func testExpiredResumeDataIsSalvagedAndRangedThroughTheCanonicalURL() async throws {
        let weights = randomData(4 << 20)
        let (server, store) = try serve(weights: weights, expiresIn: 30)

        let kept = try await pauseMidway(store)
        let before = server.requests.count
        let state = await run(ModelDownloader(store: store, configuration: .ephemeral))
        XCTAssertEqual(state, .ready(directory: store.directory))
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("w.data")), weights)
        let resumed = server.requests[before...]
        XCTAssertEqual(resumed.first { $0.path == "/resolve/w.data" }?.rangeStart, kept, "re-resolved from the kept byte")
        XCTAssertFalse(resumed.contains { $0.path.hasSuffix("w.data") && ($0.rangeStart ?? 0) < kept }, "nothing refetched")
    }

    func testRejectedResumeDataFailsThenRetriesFromThePart() async throws {
        let weights = randomData(1 << 20)
        let (server, store) = try serve(weights: weights, expiresIn: 3600)
        defer { withExtendedLifetime(server) {} }
        try store.prepare()
        try weights.prefix(1000).write(to: store.partURL(store.manifest.weights))
        store.saveResumeData(Data("not resume data".utf8), for: store.manifest.weights)

        let downloader = ModelDownloader(store: store, configuration: .ephemeral)
        guard case .failed = await run(downloader) else { return XCTFail("bad resume data should fail") }
        XCTAssertEqual(store.keptBytes(store.manifest.weights), 1000, "kept bytes survive the failure")
        let retried = await run(downloader)
        XCTAssertEqual(retried, .ready(directory: store.directory))
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("w.data")), weights)
    }

    func testLandingKeepsOnlyBytesThatFitTheManifest() {
        XCTAssertEqual(Landing.decide(offset: 0, expected: 10, status: 200, received: 10), .append)
        XCTAssertEqual(Landing.decide(offset: 4, expected: 10, status: 206, received: 6), .append)
        XCTAssertEqual(Landing.decide(offset: 4, expected: 10, status: 200, received: 10), .replace, "Range ignored")
        XCTAssertEqual(Landing.decide(offset: 0, expected: 10, status: nil, received: 10), .append, "file: URLs")
        XCTAssertEqual(Landing.decide(offset: 4, expected: 10, status: 403, received: 6), .reject("HTTP 403"))
        guard case .reject = Landing.decide(offset: 4, expected: 10, status: 206, received: 5) else { return XCTFail("short") }
        guard case .reject = Landing.decide(offset: 4, expected: 10, status: 206, received: 10) else { return XCTFail("long") }
    }

    func testResumeDataIsSalvagedOnlyNearItsSignedURLsExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let info = try XCTUnwrap(ResumeInfo(resumeData(temp: "CFNetworkDownload_x.tmp", bytes: 412, expires: 1_000_030)))
        XCTAssertEqual(info, ResumeInfo(tempFileName: "CFNetworkDownload_x.tmp", bytesReceived: 412,
                                        expiresAt: Date(timeIntervalSince1970: 1_000_030)))
        XCTAssertEqual(info.step(now: now), .salvage(tempFileName: "CFNetworkDownload_x.tmp", bytes: 412))
        XCTAssertEqual(info.step(now: now.addingTimeInterval(-3600)), .resume)
        XCTAssertEqual(ResumeInfo(tempFileName: nil, bytesReceived: 412, expiresAt: now).step(now: now), .discard)
        XCTAssertEqual(ResumeInfo(tempFileName: "t", bytesReceived: 0, expiresAt: now).step(now: now), .discard)
        XCTAssertEqual(ResumeInfo(tempFileName: "t", bytesReceived: 9, expiresAt: nil).step(now: now), .resume, "unsigned URL")
        XCTAssertNil(ResumeInfo(Data("junk".utf8)))
    }

    func testFetchContinuesFromThePartPlusSalvagedBytes() throws {
        let temps = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temps, withIntermediateDirectories: true)
        let file = RemoteFile(name: "w.data", url: URL(string: "https://example.com/w.data")!, size: 1000)
        let manifest = ModelManifest(weights: file, archive: RemoteFile(name: "m.zip", url: file.url, size: 10), archiveEntries: [:])
        let store = ModelStore(directory: root.appendingPathComponent("m"), manifest: manifest, temporaryDirectories: [temps])
        try store.prepare()
        try Data(repeating: 1, count: 100).write(to: store.partURL(file))
        try Data(repeating: 2, count: 80).write(to: temps.appendingPathComponent("CFNetworkDownload_x.tmp"))
        let now = Date()
        store.saveResumeData(resumeData(temp: "CFNetworkDownload_x.tmp", bytes: 50, expires: now.timeIntervalSince1970 - 1), for: file)

        XCTAssertEqual(store.progress().received, 150 + manifest.archive.size, "bytes behind resume data count before they are salvaged")
        XCTAssertEqual(store.fetch(file, now: now), .range(offset: 150))
        XCTAssertEqual(try Data(contentsOf: store.partURL(file)), Data(repeating: 1, count: 100) + Data(repeating: 2, count: 50))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.resumeURL(file).path))
        XCTAssertEqual(store.fetch(file, now: now), .range(offset: 150), "fetching again is idempotent")

        let live = resumeData(temp: "t", bytes: 5, expires: now.timeIntervalSince1970 + 3600)
        store.saveResumeData(live, for: file)
        XCTAssertEqual(store.fetch(file, now: now), .resumeData(live, offset: 150))
    }

    func testPrepareSettlesPartsACrashLeftBehind() throws {
        let file = RemoteFile(name: "w.data", url: URL(string: "https://example.com/w.data")!, size: 10)
        let archive = RemoteFile(name: "m.zip", url: file.url, size: 4)
        let store = ModelStore(directory: root.appendingPathComponent("m"),
                               manifest: ModelManifest(weights: file, archive: archive, archiveEntries: ["x": 1]))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: store.partURL(file))
        try Data(repeating: 1, count: 9).write(to: store.partURL(archive))
        try store.prepare()
        XCTAssertEqual(store.pending(), [archive], "a complete part is promoted, an oversized one dropped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.partURL(archive).path))
    }

    // MARK: - Helpers

    private func makeModel(in remote: URL, weights: Data, url: (String) -> URL) throws -> (ModelManifest, [String: Data]) {
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try weights.write(to: remote.appendingPathComponent("w.data"))
        let entries = ["encoder.int8.onnx": Data("enc".utf8), "tokens.txt": Data("a\nb\n".utf8)]
        for (name, data) in entries { try data.write(to: remote.appendingPathComponent(name)) }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = remote
        zip.arguments = ["-q", "-0", "-X", "m.zip"] + entries.keys.sorted()
        try zip.run()
        zip.waitUntilExit()
        let zipSize = (try FileManager.default.attributesOfItem(atPath: remote.appendingPathComponent("m.zip").path)[.size] as! NSNumber).uint64Value
        let manifest = ModelManifest(
            weights: RemoteFile(name: "w.data", url: url("w.data"), size: UInt64(weights.count)),
            archive: RemoteFile(name: "m.zip", url: url("m.zip"), size: zipSize),
            archiveEntries: entries.mapValues { UInt64($0.count) })
        return (manifest, entries)
    }

    private func serve(weights: Data, expiresIn: TimeInterval) throws -> (RangeServer, ModelStore) {
        let remote = root.appendingPathComponent("remote")
        let (manifest, _) = try makeModel(in: remote, weights: weights) { remote.appendingPathComponent($0) }
        let files = try ["w.data", "m.zip"].reduce(into: [String: Data]()) {
            $0[$1] = try Data(contentsOf: remote.appendingPathComponent($1))
        }
        let server = try RangeServer(files: files, expiresIn: expiresIn)
        let served = ModelManifest(
            weights: RemoteFile(name: "w.data", url: server.url("w.data"), size: manifest.weights.size),
            archive: RemoteFile(name: "m.zip", url: server.url("m.zip"), size: manifest.archive.size),
            archiveEntries: manifest.archiveEntries)
        return (server, ModelStore(directory: root.appendingPathComponent("Models/m"), manifest: served))
    }

    /// Starts the download, pauses it once a quarter of the weights are in, and returns the bytes kept.
    private func pauseMidway(_ store: ModelStore) async throws -> UInt64 {
        let downloader = ModelDownloader(store: store, configuration: .ephemeral)
        let states = stream(downloader)
        downloader.start()
        let quarter = store.manifest.archive.size + store.manifest.weights.size / 4
        for await state in states {
            if case .downloading(let progress) = state, progress.received >= quarter { break }
        }
        downloader.pause()
        let resume = store.resumeURL(store.manifest.weights)
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: resume.path) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let info = try XCTUnwrap(ResumeInfo(Data(contentsOf: resume)), "pausing should keep resume data")
        XCTAssertGreaterThan(info.bytesReceived, 0)
        XCTAssertLessThan(info.bytesReceived, store.manifest.weights.size, "paused before the end")
        return info.bytesReceived
    }

    private func stream(_ downloader: ModelDownloader) -> AsyncStream<ModelState> {
        AsyncStream { continuation in downloader.observe { continuation.yield($0) } }
    }

    private func next(_ downloader: ModelDownloader) async -> ModelState? {
        for await state in stream(downloader) { return state }
        return nil
    }

    private func run(_ downloader: ModelDownloader) async -> ModelState? {
        if case .ready? = await next(downloader) { return .ready(directory: downloader.store.directory) }
        let states = stream(downloader)
        downloader.start()
        var started = false
        for await state in states {
            switch state {
            case .downloading: started = true
            case .ready: return state
            case .failed where started: return state
            default: break
            }
        }
        return nil
    }

    private func randomData(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    private func resumeData(temp: String, bytes: UInt64, expires: TimeInterval) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        let info: NSDictionary = [
            "NSURLSessionResumeInfoTempFileName": temp,
            "NSURLSessionResumeBytesReceived": NSNumber(value: bytes),
            "NSURLSessionDownloadURL": "https://cdn.example.com/x?Expires=\(Int(expires))&Signature=s",
        ]
        archiver.encode(info, forKey: "NSKeyedArchiveRootObjectKey")
        return archiver.encodedData
    }
}
