import Foundation

public enum ModelState: Equatable, Sendable {
    case missing
    case downloading(progress: Double)
    case ready(directory: URL)
    case failed(reason: String)
}

public struct RemoteFile: Sendable {
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

/// Converges a directory to a ready model. Every step is derived from what is on disk, so re-running after a
/// crash or a failed download only fetches what is missing; finished files are never fetched again.
public actor ModelStore {
    public nonisolated let directory: URL
    public nonisolated let manifest: ModelManifest
    private let session: URLSession

    public init(directory: URL, manifest: ModelManifest = .openThaiInt8, session: URLSession = .shared) {
        self.directory = directory
        self.manifest = manifest
        self.session = session
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/openthai2.0-asr-streaming-int8", isDirectory: true)
    }

    public nonisolated func diskState() -> ModelState {
        missingEntries().isEmpty && has(manifest.weights.name, size: manifest.weights.size)
            ? .ready(directory: directory) : .missing
    }

    public func ensureReady(progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> ModelState {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var root = directory.deletingLastPathComponent()
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try root.setResourceValues(values)

            var downloads: [RemoteFile] = []
            if !has(manifest.weights.name, size: manifest.weights.size) { downloads.append(manifest.weights) }
            if !missingEntries().isEmpty && !has(manifest.archive.name, size: manifest.archive.size) {
                downloads.append(manifest.archive)
            }
            let total = Double(downloads.reduce(0) { $0 + $1.size })
            var finished = 0.0
            for file in downloads {
                let done = finished
                try await download(file) { bytes in progress(total > 0 ? (done + Double(bytes)) / total : 1) }
                finished += Double(file.size)
            }

            let missing = missingEntries()
            if !missing.isEmpty {
                let zip = try StoredZip(url: url(manifest.archive.name))
                for name in missing {
                    guard let entry = zip.entry(named: name) else { throw StoredZipError.unsupported("no \(name) in archive") }
                    try zip.extract(entry, to: url(name))
                }
            }
            if missingEntries().isEmpty { try? FileManager.default.removeItem(at: url(manifest.archive.name)) }

            let state = diskState()
            return state == .missing ? .failed(reason: "Model files are incomplete after download") : state
        } catch {
            return .failed(reason: String(describing: error))
        }
    }

    private nonisolated func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    private nonisolated func has(_ name: String, size: UInt64) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url(name).path)
        return (attributes?[.size] as? NSNumber)?.uint64Value == size
    }

    private nonisolated func missingEntries() -> [String] {
        manifest.archiveEntries.filter { !has($0.key, size: $0.value) }.map(\.key).sorted()
    }

    private func download(_ file: RemoteFile, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        let destination = url(file.name)
        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let downloadSession = URLSession(
            configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        defer { downloadSession.finishTasksAndInvalidate() }
        try await delegate.run(downloadSession.downloadTask(with: file.url))
        guard has(file.name, size: file.size) else {
            try? FileManager.default.removeItem(at: destination)
            throw URLError(.cannotDecodeContentData, userInfo: [NSLocalizedDescriptionKey: "\(file.name) has the wrong size"])
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (UInt64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?

    init(destination: URL, progress: @escaping @Sendable (UInt64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func run(_ task: URLSessionDownloadTask) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        progress(UInt64(totalBytesWritten))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            moveError = URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            return
        }
        do {
            _ = try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error ?? moveError {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
