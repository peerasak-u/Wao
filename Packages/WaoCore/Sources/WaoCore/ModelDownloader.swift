import Foundation

/// Runs the model's transfers on one URLSession, which in the app is a background session that keeps going
/// while the app is suspended or terminated. The files in the store are the truth; this only tracks the
/// transfers in flight. All state is touched on `queue`, the session's delegate queue.
public final class ModelDownloader: NSObject, @unchecked Sendable {
    public let store: ModelStore
    private let now: @Sendable () -> Date
    private let queue = OperationQueue()
    private var session: URLSession!
    private var tasks: [String: URLSessionDownloadTask] = [:]
    /// Bytes each running transfer holds beyond its file's `.part`.
    private var written: [String: UInt64] = [:]
    private var failure: String?
    private var paused = false
    private var adopting = true
    private var startAfterAdopting = false
    private var published: ModelState?
    private var observer: (@Sendable (ModelState) -> Void)?
    private var backgroundCompletion: (@Sendable () -> Void)?

    public init(store: ModelStore, configuration: URLSessionConfiguration, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
        super.init()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        session.getAllTasks { [self] running in
            queue.addOperation { [self] in adopt(running) }
        }
    }

    /// Delivers every state change on the session's queue, starting with the current one.
    public func observe(_ handler: @escaping @Sendable (ModelState) -> Void) {
        queue.addOperation { [self] in
            observer = handler
            published = nil
            publish()
        }
    }

    /// Starts, resumes, or retries: whatever is missing is fetched from the last byte kept.
    public func start() {
        queue.addOperation { [self] in
            if adopting { startAfterAdopting = true } else { converge() }
        }
    }

    public func pause() {
        queue.addOperation { [self] in
            guard !tasks.isEmpty else { return }
            paused = true
            for task in tasks.values { task.cancel(byProducingResumeData: { _ in }) }
            publish()
        }
    }

    public func handleBackgroundEvents(completion: @escaping @Sendable () -> Void) {
        queue.addOperation { [self] in backgroundCompletion = completion }
    }

    /// Transfers a background session kept running while the app was gone are picked up where they are.
    private func adopt(_ running: [URLSessionTask]) {
        for case let task as URLSessionDownloadTask in running {
            guard let tag = Tag(task.taskDescription), let file = file(named: tag.name), tasks[tag.name] == nil,
                  store.keptBytes(file) == tag.offset else {
                task.cancel()
                continue
            }
            tasks[tag.name] = task
            written[tag.name] = UInt64(max(0, task.countOfBytesReceived))
            if task.state == .suspended { task.resume() }
        }
        adopting = false
        if startAfterAdopting { converge() } else { publish() }
    }

    private func converge() {
        failure = nil
        paused = false
        do {
            try store.prepare()
        } catch {
            fail(String(describing: error))
            return
        }
        for file in store.pending() where tasks[file.name] == nil {
            let fetch = store.fetch(file, now: now())
            let task: URLSessionDownloadTask
            switch fetch {
            case .resumeData(let data, _):
                task = session.downloadTask(withResumeData: data)
                written[file.name] = ResumeInfo(data)?.bytesReceived ?? 0
            case .range(let offset):
                var request = URLRequest(url: file.url)
                if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
                task = session.downloadTask(with: request)
                written[file.name] = 0
            }
            task.taskDescription = Tag(name: file.name, offset: fetch.offset).description
            tasks[file.name] = task
            task.resume()
        }
        if tasks.isEmpty { finishIfLanded() }
        publish()
    }

    private func finishIfLanded() {
        guard store.pending().isEmpty, !store.isReady else { return }
        do { try store.finish() } catch { failure = String(describing: error) }
    }

    /// Stops the other transfers too, keeping their resume data, so one retry restarts everything.
    private func fail(_ reason: String) {
        if failure == nil { failure = reason }
        for task in tasks.values { task.cancel(byProducingResumeData: { _ in }) }
        publish()
    }

    private var state: ModelState {
        if !tasks.isEmpty {
            let progress = store.progress(inFlight: written)
            return paused ? .paused(progress) : .downloading(progress)
        }
        if let failure { return .failed(reason: failure, progress: store.progress()) }
        let state = store.state()
        return paused && state == .missing ? .paused(store.progress()) : state
    }

    private func publish() {
        let state = state
        if case .downloading(let new) = state, case .downloading(let old)? = published,
           new.received < old.received + 1_000_000 { return }
        guard state != published else { return }
        published = state
        observer?(state)
    }

    private func file(named name: String) -> RemoteFile? { store.manifest.files.first { $0.name == name } }

    private func tracked(_ task: URLSessionTask) -> (Tag, RemoteFile)? {
        guard let tag = Tag(task.taskDescription), tasks[tag.name] === task, let file = file(named: tag.name) else { return nil }
        return (tag, file)
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let (tag, _) = tracked(downloadTask) else { return }
        written[tag.name] = UInt64(totalBytesWritten)
        publish()
    }

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        guard let (tag, _) = tracked(downloadTask) else { return }
        written[tag.name] = UInt64(fileOffset)
        publish()
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (tag, file) = tracked(downloadTask) else { return }
        do {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
            try store.land(location, for: file, offset: tag.offset, status: status)
        } catch {
            if failure == nil { failure = String(describing: error) }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (tag, file) = tracked(task) else { return }
        tasks[tag.name] = nil
        written[tag.name] = nil
        if let error = error as NSError? {
            if let data = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { store.saveResumeData(data, for: file) }
            let pausedByUser = paused && error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
            if !pausedByUser { fail(error.localizedDescription) }
        } else if failure != nil {
            fail(failure!)
        }
        if tasks.isEmpty && failure == nil { finishIfLanded() }
        publish()
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = backgroundCompletion
        backgroundCompletion = nil
        DispatchQueue.main.async { completion?() }
    }
}

/// Persisted on each task as its description, so a relaunched app knows which file and offset a transfer is for.
private struct Tag: CustomStringConvertible {
    let name: String
    let offset: UInt64

    init(name: String, offset: UInt64) {
        self.name = name
        self.offset = offset
    }

    init?(_ description: String?) {
        guard let parts = description?.split(separator: "|"), parts.count == 2, let value = UInt64(parts[1]) else { return nil }
        name = String(parts[0])
        offset = value
    }

    var description: String { "\(name)|\(offset)" }
}
