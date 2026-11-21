import Foundation

public struct DownloadProgress: Equatable, Sendable {
    public let received: UInt64
    public let total: UInt64

    public init(received: UInt64, total: UInt64) {
        self.received = received
        self.total = total
    }

    public var fraction: Double { total > 0 ? Double(received) / Double(total) : 0 }
}

public enum ModelState: Equatable, Sendable {
    case missing
    case downloading(DownloadProgress)
    case paused(DownloadProgress)
    case ready(directory: URL)
    case failed(reason: String, progress: DownloadProgress)
}

public struct RemoteFile: Sendable, Equatable {
    public let name: String
    public let url: URL
    public let size: UInt64

    public init(name: String, url: URL, size: UInt64) {
        self.name = name
        self.url = url
        self.size = size
    }
}

/// What a ready model directory holds and where each piece comes from.
public struct ModelManifest: Sendable {
    public let weights: RemoteFile
    public let archive: RemoteFile
    /// Entries of `archive`, extracted beside `weights`, with their sizes.
    public let archiveEntries: [String: UInt64]

    public init(weights: RemoteFile, archive: RemoteFile, archiveEntries: [String: UInt64]) {
        self.weights = weights
        self.archive = archive
        self.archiveEntries = archiveEntries
    }

    public var files: [RemoteFile] { [weights, archive] }

    public static let openThaiInt8: ModelManifest = {
        let base = URL(string: "https://huggingface.co/iapp/OpenThai2.0-ASR-Streaming-ONNX/resolve/main/")!
        return ModelManifest(
            weights: RemoteFile(
                name: "encoder.int8.onnx.data", url: base.appendingPathComponent("encoder.int8.onnx.data"),
                size: 883_175_424),
            archive: RemoteFile(
                name: "openthai2.0-asr-streaming-int8.asr.zip",
                url: base.appendingPathComponent("openthai2.0-asr-streaming-int8.asr.zip"), size: 109_014_005),
            archiveEntries: ["encoder.int8.onnx": 1_589_571, "decoder_joint.onnx": 107_330_778, "tokens.txt": 93_160])
    }()
}

/// How to continue fetching one file, decided from what is on disk.
public enum Fetch: Equatable, Sendable {
    case resumeData(Data, offset: UInt64)
    /// A plain GET from the canonical URL; `offset > 0` asks for `Range: bytes=offset-` to append to the `.part`.
    case range(offset: UInt64)

    public var offset: UInt64 {
        switch self {
        case .resumeData(_, let offset), .range(let offset): offset
        }
    }
}

/// Converges a directory to a ready model. Every step is derived from what is on disk, so re-running after a
/// crash, a pause, or a failed download only fetches what is missing, from the last byte kept.
///
/// Per remote file the directory holds at most: the finished file; a `.part` with a verified prefix; and a
/// `.resume` with URLSession resume data whose bytes continue the `.part`.
public struct ModelStore: Sendable {
    public let directory: URL
    public let manifest: ModelManifest
    /// Where URLSession keeps the bytes behind a resume data blob, searched when salvaging them into a `.part`.
    public let temporaryDirectories: [URL]

    public init(directory: URL, manifest: ModelManifest = .openThaiInt8,
                temporaryDirectories: [URL] = ModelStore.defaultTemporaryDirectories) {
        self.directory = directory
        self.manifest = manifest
        self.temporaryDirectories = temporaryDirectories
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/openthai2.0-asr-streaming-int8", isDirectory: true)
    }

    public static var defaultTemporaryDirectories: [URL] {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let background = caches.appendingPathComponent("com.apple.nsurlsessiond/Downloads/\(Bundle.main.bundleIdentifier ?? "")")
        return [FileManager.default.temporaryDirectory, background]
    }

    /// Ready, or the bytes kept so far; `inFlight` adds what running transfers hold beyond each `.part`.
    public func state(inFlight: [String: UInt64] = [:]) -> ModelState {
        if isReady { return .ready(directory: directory) }
        let progress = progress(inFlight: inFlight)
        return progress.received > 0 ? .paused(progress) : .missing
    }

    public func progress(inFlight: [String: UInt64] = [:]) -> DownloadProgress {
        let total = manifest.files.reduce(0) { $0 + $1.size }
        let received = manifest.files.reduce(UInt64(0)) { sum, file in
            if isDone(file) { return sum + file.size }
            let extra = inFlight[file.name] ?? resumeInfo(file)?.bytesReceived ?? 0
            return sum + min(file.size, size(of: partURL(file)) + extra)
        }
        return DownloadProgress(received: received, total: total)
    }

    public var isReady: Bool { missingEntries().isEmpty && has(manifest.weights.name, size: manifest.weights.size) }

    public func pending() -> [RemoteFile] { manifest.files.filter { !isDone($0) } }

    /// Creates the directory and settles `.part` files a crash left complete or oversized.
    public func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var root = directory.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        for file in pending() {
            let part = size(of: partURL(file))
            if part == file.size { try promote(file) }
            if part > file.size { discardPartial(file) }
        }
    }

    /// Prefers live resume data. Resume data past its signed URL's expiry is salvaged instead: its bytes are
    /// appended to the `.part` and the rest is fetched with a Range request that re-resolves the canonical URL.
    public func fetch(_ file: RemoteFile, now: Date = Date()) -> Fetch {
        let resume = resumeURL(file)
        defer { try? FileManager.default.removeItem(at: resume) }
        let offset = keptBytes(file)
        guard let data = try? Data(contentsOf: resume) else { return .range(offset: offset) }
        let info = ResumeInfo(data)
        switch info?.step(now: now) ?? .resume {
        case .resume:
            return .resumeData(data, offset: offset)
        case .salvage(let name, let bytes):
            return .range(offset: (try? salvage(name, bytes: bytes, into: file)) ?? offset)
        case .discard:
            return .range(offset: offset)
        }
    }

    public func saveResumeData(_ data: Data, for file: RemoteFile) {
        try? data.write(to: resumeURL(file), options: .atomic)
    }

    /// Takes a finished transfer that started at `offset` and keeps its bytes only if they fit the manifest.
    public func land(_ location: URL, for file: RemoteFile, offset: UInt64, status: Int?) throws {
        let part = partURL(file)
        guard size(of: part) == offset else { throw StoreError("\(file.name) changed on disk during the download") }
        switch Landing.decide(offset: offset, expected: file.size, status: status, received: size(of: location)) {
        case .append:
            if offset == 0 {
                try? FileManager.default.removeItem(at: part)
                try FileManager.default.moveItem(at: location, to: part)
            } else {
                try append(location, to: part)
            }
        case .replace:
            try? FileManager.default.removeItem(at: part)
            try FileManager.default.moveItem(at: location, to: part)
        case .reject(let reason):
            throw StoreError("\(file.name): \(reason)")
        }
        try promote(file)
    }

    /// Extracts what the archive holds once every download has landed.
    public func finish() throws {
        let missing = missingEntries()
        if !missing.isEmpty {
            let zip = try StoredZip(url: url(manifest.archive.name))
            for name in missing {
                guard let entry = zip.entry(named: name) else { throw StoredZipError.unsupported("no \(name) in archive") }
                try zip.extract(entry, to: url(name))
            }
        }
        if missingEntries().isEmpty { try? FileManager.default.removeItem(at: url(manifest.archive.name)) }
        guard isReady else { throw StoreError("Model files are incomplete after download") }
    }

    public func keptBytes(_ file: RemoteFile) -> UInt64 { size(of: partURL(file)) }

    public func partURL(_ file: RemoteFile) -> URL { url(file.name + ".part") }
    public func resumeURL(_ file: RemoteFile) -> URL { url(file.name + ".resume") }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    private func size(of url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func has(_ name: String, size expected: UInt64) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path) && size(of: url(name)) == expected
    }

    private func isDone(_ file: RemoteFile) -> Bool {
        has(file.name, size: file.size) || (file == manifest.archive && missingEntries().isEmpty)
    }

    private func missingEntries() -> [String] {
        manifest.archiveEntries.filter { !has($0.key, size: $0.value) }.map(\.key).sorted()
    }

    private func resumeInfo(_ file: RemoteFile) -> ResumeInfo? {
        (try? Data(contentsOf: resumeURL(file))).flatMap(ResumeInfo.init)
    }

    private func promote(_ file: RemoteFile) throws {
        let part = partURL(file)
        guard size(of: part) == file.size else { return }
        try? FileManager.default.removeItem(at: url(file.name))
        try FileManager.default.moveItem(at: part, to: url(file.name))
    }

    private func discardPartial(_ file: RemoteFile) {
        try? FileManager.default.removeItem(at: partURL(file))
        try? FileManager.default.removeItem(at: resumeURL(file))
    }

    private func salvage(_ tempName: String, bytes: UInt64, into file: RemoteFile) throws -> UInt64 {
        let part = partURL(file)
        guard let temp = temporaryDirectories.map({ $0.appendingPathComponent(tempName) })
            .first(where: { size(of: $0) >= bytes }) else { throw StoreError("no bytes behind the resume data") }
        if !FileManager.default.fileExists(atPath: part.path) { FileManager.default.createFile(atPath: part.path, contents: nil) }
        try append(temp, to: part, limit: bytes)
        try? FileManager.default.removeItem(at: temp)
        return size(of: part)
    }

    private func append(_ source: URL, to destination: URL, limit: UInt64 = .max) throws {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }
        try writer.seekToEnd()
        var remaining = limit
        while remaining > 0 {
            let chunk = try reader.read(upToCount: Int(min(remaining, 4 << 20))) ?? Data()
            if chunk.isEmpty { break }
            try writer.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
        }
    }
}

public struct StoreError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

/// What to do with a finished transfer that started at `offset`.
public enum Landing: Equatable {
    case append
    /// The server ignored the Range request and sent the whole file.
    case replace
    case reject(String)

    /// `status` is nil for non-HTTP transfers such as `file:` URLs.
    public static func decide(offset: UInt64, expected: UInt64, status: Int?, received: UInt64) -> Landing {
        let status = status ?? 200
        guard (200..<300).contains(status) else { return .reject("HTTP \(status)") }
        if offset + received == expected { return .append }
        if status == 200 && received == expected { return .replace }
        return .reject("got \(received) bytes from offset \(offset), expected \(expected) in all")
    }
}

/// The parts of an opaque URLSession resume data blob needed to judge whether it can still resume.
public struct ResumeInfo: Equatable {
    public let tempFileName: String?
    public let bytesReceived: UInt64
    /// From the `Expires` query of the signed CDN URL the transfer was redirected to.
    public let expiresAt: Date?

    public enum Step: Equatable {
        case resume
        case salvage(tempFileName: String, bytes: UInt64)
        case discard
    }

    public init?(_ data: Data) {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        guard let info = unarchiver.decodeObject(forKey: "NSKeyedArchiveRootObjectKey") as? [String: Any] else { return nil }
        tempFileName = info["NSURLSessionResumeInfoTempFileName"] as? String
        bytesReceived = (info["NSURLSessionResumeBytesReceived"] as? NSNumber)?.uint64Value ?? 0
        let expires = (info["NSURLSessionDownloadURL"] as? String).flatMap(URLComponents.init(string:))?
            .queryItems?.first { $0.name == "Expires" }?.value.flatMap(TimeInterval.init)
        expiresAt = expires.map(Date.init(timeIntervalSince1970:))
    }

    public init(tempFileName: String?, bytesReceived: UInt64, expiresAt: Date?) {
        self.tempFileName = tempFileName
        self.bytesReceived = bytesReceived
        self.expiresAt = expiresAt
    }

    /// A minute of slack, because the resumed request reaches the CDN some time after this check.
    public func step(now: Date) -> Step {
        guard let expiresAt, expiresAt.timeIntervalSince(now) < 60 else { return .resume }
        guard let tempFileName, bytesReceived > 0 else { return .discard }
        return .salvage(tempFileName: tempFileName, bytes: bytesReceived)
    }
}
