import AVFoundation
import SwiftUI
import WaoCore
import WaoInference

@MainActor
final class AppModel: ObservableObject {
    struct LoadReport {
        var seconds: Double
        var availableBefore: UInt64?
        var availableAfter: UInt64?
        var footprintBefore: UInt64
        var footprintAfter: UInt64
    }

    @Published private(set) var model: ModelState
    @Published private(set) var session: SessionState = .off
    @Published private(set) var lastResult: Transcription?
    @Published private(set) var loadReport: LoadReport?
    @Published private(set) var loadedThreads: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var isTranscribingFile = false
    @Published var threads = 1
    @Published var error: String?
    @Published var micPermission = AVAudioApplication.shared.recordPermission

    let store = ModelStore(directory: ModelStore.defaultDirectory)
    private var dictation: DictationSession!
    private var interruptionObserver: NSObjectProtocol?

    init() {
        model = store.diskState()
        let bridge = try? Bridge.shared()
        dictation = DictationSession(bridge: bridge) { [weak self] snapshot in
            Task { @MainActor in
                self?.session = snapshot.state
                self?.lastResult = snapshot.lastResult
            }
        }
        Task { await dictation.listenForKeyboard() }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { await self?.dictation.end() }
        }
        if bridge == nil { error = "App Group container unavailable; the keyboard cannot reach the app." }
    }

    var isSessionLive: Bool { session != .off }

    func download() async {
        model = .downloading(progress: 0)
        let state = await store.ensureReady { progress in
            Task { @MainActor [weak self] in
                if case .downloading = self?.model { self?.model = .downloading(progress: progress) }
            }
        }
        model = state
    }

    func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
        micPermission = AVAudioApplication.shared.recordPermission
    }

    /// Loads (or reloads with a new thread count) the transcriber, measuring memory around it.
    func loadModel() async {
        guard case .ready(let directory) = model, loadedThreads != threads, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let threads = threads
        if loadedThreads != nil {
            await dictation.use(nil)
            loadedThreads = nil
        }
        let availableBefore = MemoryProbe.availableBytes(), footprintBefore = MemoryProbe.footprintBytes()
        let start = Date()
        do {
            let transcriber = try await Task.detached(priority: .userInitiated) {
                try Transcriber(modelDirectory: directory, threads: threads)
            }.value
            await dictation.use(transcriber)
            loadedThreads = threads
            loadReport = LoadReport(
                seconds: Date().timeIntervalSince(start), availableBefore: availableBefore,
                availableAfter: MemoryProbe.availableBytes(), footprintBefore: footprintBefore,
                footprintAfter: MemoryProbe.footprintBytes())
        } catch {
            self.error = "Model load failed: \(error)"
        }
    }

    func beginSession() async {
        if micPermission == .undetermined { await requestMicrophone() }
        guard micPermission == .granted else {
            error = "ต้องอนุญาตไมโครโฟนก่อน"
            return
        }
        await loadModel()
        do {
            try await dictation.begin()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func endSession() async {
        await dictation.end()
    }

    func record(_ kind: Command.Kind) async {
        if !isSessionLive { await beginSession() }
        await dictation.sendLocal(kind)
    }

    func transcribeSample(_ url: URL, language: Language) async {
        await loadModel()
        isTranscribingFile = true
        defer { isTranscribingFile = false }
        do {
            _ = try await dictation.transcribe(file: url, language: language)
        } catch {
            self.error = "Transcription failed: \(error)"
        }
    }
}
