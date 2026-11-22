import AVFoundation
import Combine
import SwiftUI
import WaoCore
import WaoInference

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var model: ModelState
    enum MicTest: Equatable {
        case ready
        case recording(since: Date, heard: Heard?)
        case transcribing(heard: Heard?)
        case done(Transcription)
    }

    @Published private(set) var session: SessionState = .off
    @Published private(set) var test = MicTest.ready
    /// The mic test opened the session itself and will close it again; the user has not started one.
    @Published private(set) var testOwnsSession = false
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var micPermission = AVAudioApplication.shared.recordPermission
    @Published var vocabulary = VocabularyStore.load()

    private let downloader = AppDelegate.downloader
    private var dictation: DictationSession!
    private var interruptionObserver: NSObjectProtocol?
    private var memoryWarningObserver: NSObjectProtocol?
    private var vocabularyCommit: AnyCancellable?
    private var testID: UUID?
    private var testStartedAt = Date()

    init() {
        model = downloader.store.state()
        downloader.observe { state in
            DispatchQueue.main.async { [weak self] in self?.model = state }
        }
        let bridge = try? Bridge.shared()
        dictation = DictationSession(bridge: bridge, hotwords: vocabulary.hotwords) { [weak self] snapshot in
            Task { @MainActor in self?.observe(snapshot) }
        }
        Task { await dictation.listenForKeyboard() }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { await self?.dictation.end() }
        }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.dictation.releaseModel() }
        }
        if bridge == nil { error = "App Group container unavailable; the keyboard cannot reach the app." }
        vocabularyCommit = $vocabulary.dropFirst().removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] book in self?.commit(book) }
    }

    /// iOS may kill a backgrounded app before the debounced save fires.
    func commitVocabularyNow() {
        commit(vocabulary)
    }

    private func commit(_ book: VocabularyBook) {
        do {
            try VocabularyStore.save(book)
        } catch {
            self.error = "บันทึกคลังคำศัพท์ไม่สำเร็จ: \(error.localizedDescription)"
        }
        let hotwords = book.hotwords
        Task { await dictation.use(hotwords: hotwords) }
    }

    var isSessionLive: Bool { session != .off }
    var isKeyboardSessionOn: Bool { isSessionLive && !testOwnsSession }

    /// Starts, resumes, or retries; whatever is on disk is kept.
    func download() {
        downloader.start()
    }

    func pauseDownload() {
        downloader.pause()
    }

    func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
        micPermission = AVAudioApplication.shared.recordPermission
    }

    func loadModel() async {
        guard case .ready(let directory) = model, !isLoading, await !dictation.isModelLoaded else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await dictation.load(from: directory)
        } catch {
            self.error = "Model load failed: \(error)"
        }
    }

    func beginSession() async {
        testOwnsSession = false
        await openSession()
    }

    @discardableResult
    private func openSession() async -> Bool {
        if micPermission == .undetermined { await requestMicrophone() }
        guard micPermission == .granted else {
            error = "ต้องอนุญาตไมโครโฟนก่อน"
            return false
        }
        await loadModel()
        do {
            try await dictation.begin()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func endSession() async {
        await dictation.end()
    }

    func toggleTest() async {
        switch test {
        case .recording: await dictation.sendLocal(Command(kind: .stop))
        case .transcribing: break
        case .ready, .done: await startTest()
        }
    }

    private func startTest() async {
        if isSessionLive {
            await loadModel()
        } else {
            testOwnsSession = true
            guard await openSession() else {
                testOwnsSession = false
                return
            }
        }
        let start = Command(kind: .start(.thaiEnglishMix))
        testID = start.id
        testStartedAt = Date()
        await dictation.sendLocal(start)
    }

    private func observe(_ snapshot: DictationSession.Snapshot) {
        session = snapshot.state
        if snapshot.state == .off { testOwnsSession = false }
        guard let id = testID else { return }
        switch snapshot.state {
        case .listening(let current, _, let heard) where current == id:
            test = .recording(since: testStartedAt, heard: heard)
        case .transcribing(let current) where current == id:
            if case .recording(_, let heard) = test { test = .transcribing(heard: heard) } else { test = .transcribing(heard: nil) }
        case .done(let current, _) where current == id:
            finishTest()
            test = snapshot.lastResult.map(MicTest.done) ?? .ready
        case .failed(let current, let reason) where current == id:
            finishTest()
            test = .ready
            error = "ถอดเสียงไม่สำเร็จ: \(reason)"
        case .off:
            // The session closed under the test: ended by the user, an interruption, or the idle timer.
            testID = nil
            test = .ready
        default:
            break
        }
    }

    /// Leaves the session as the test found it: closed if the test opened it, otherwise back to waiting.
    private func finishTest() {
        testID = nil
        let close = testOwnsSession
        Task {
            if close {
                await dictation.end()
            } else {
                try? await dictation.begin()
            }
        }
    }
}

extension AppModel.MicTest {
    enum Step { case ready, recording, transcribing, done }

    var step: Step {
        switch self {
        case .ready: .ready
        case .recording: .recording
        case .transcribing: .transcribing
        case .done: .done
        }
    }

    var isRecording: Bool { step == .recording }
    var isTranscribing: Bool { step == .transcribing }
}
