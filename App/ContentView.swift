import SwiftUI
import WaoCore
import WaoInference

@main
struct WaoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    guard url.scheme == "wao", url.host == "session" else { return }
                    Task { await model.beginSession() }
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.isSessionLive {
                    Section {
                        Label("เซสชันเปิดอยู่ กลับไปที่แอปที่คุณพิมพ์ได้เลย", systemImage: "mic.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Session on. Go back to your app and tap the mic on the keyboard.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ModelSection()
                SetupSection()
                SessionSection()
                TestPanel()
            }
            .navigationTitle("เว่า")
            .alert("เกิดข้อผิดพลาด", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
        }
    }
}

private struct ModelSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section("โมเดล (OpenThai2.0 ASR int8, ~1 GB)") {
            switch model.model {
            case .missing:
                Button("ดาวน์โหลดโมเดล (Download model)") { Task { await model.download() } }
            case .downloading(let progress):
                ProgressView(value: progress) { Text("กำลังดาวน์โหลด \(Int(progress * 100))%") }
            case .ready:
                Label("พร้อมใช้งาน (Ready, on device)", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            case .failed(let reason):
                Text(reason).font(.footnote).foregroundStyle(.red)
                Button("ลองอีกครั้ง (Retry)") { Task { await model.download() } }
            }
        }
    }
}

private struct SetupSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("ตั้งค่า (Setup)") {
            Text("1. การตั้งค่า > ทั่วไป > แป้นพิมพ์ > แป้นพิมพ์ > เพิ่มแป้นพิมพ์ใหม่ > เว่า")
            Text("2. แตะ เว่า แล้วเปิด \"อนุญาตการเข้าถึงแบบเต็ม\" (Allow Full Access)")
            HStack {
                Text("3. ไมโครโฟน")
                Spacer()
                switch model.micPermission {
                case .granted: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .denied: Text("ถูกปฏิเสธ").foregroundStyle(.red)
                default: Button("อนุญาต") { Task { await model.requestMicrophone() } }
                }
            }
            Button("เปิดการตั้งค่า (Open Settings)") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }
}

private struct SessionSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section("เซสชัน (Session)") {
            Text(model.session.summary).font(.callout.monospaced())
            if model.isSessionLive {
                Button("ปิดเซสชัน (End session)", role: .destructive) { Task { await model.endSession() } }
            } else {
                Button("เริ่มเซสชัน (Start session)") { Task { await model.beginSession() } }
                    .disabled(!model.model.isReady)
            }
            Text("ไมโครโฟนเปิดค้างไว้ระหว่างเซสชัน และปิดเองหลังไม่ใช้ 5 นาที")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct TestPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var language = Language.thai
    @State private var sample = "greeting"

    private static let samples = ["greeting", "food", "trip", "thanks"]

    var body: some View {
        Section("ทดสอบ (Test panel)") {
            Picker("ภาษา", selection: $language) {
                Text("ไทย (th-TH)").tag(Language.thai)
                Text("ไทย+อังกฤษ (th-mix)").tag(Language.thaiEnglishMix)
            }
            Picker("CPU threads", selection: $model.threads) {
                ForEach([1, 2, 4], id: \.self) { Text("\($0)").tag($0) }
            }
            HStack {
                if case .listening = model.session {
                    Button("หยุดและถอดเสียง (Stop)") { Task { await model.record(.stop) } }
                } else {
                    Button("อัดเสียง (Record)") { Task { await model.record(.start(language)) } }
                        .disabled(!model.model.isReady || model.session.isBusy)
                }
            }
            Picker("ไฟล์ตัวอย่าง", selection: $sample) {
                ForEach(Self.samples, id: \.self) { Text($0).tag($0) }
            }
            Button("ถอดเสียงไฟล์ตัวอย่าง (Transcribe sample)") {
                guard let url = Bundle.main.url(forResource: sample, withExtension: "wav", subdirectory: "samples") else { return }
                Task { await model.transcribeSample(url, language: language) }
            }
            .disabled(!model.model.isReady || model.isTranscribingFile)
            .accessibilityIdentifier("transcribe-sample")
            if model.isLoading || model.isTranscribingFile || model.session.isBusy {
                ProgressView()
            }
            if let result = model.lastResult {
                Text(result.text.isEmpty ? "(ว่าง)" : result.text)
                    .font(.title3)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("result-text")
                Metric("ความยาวเสียง (audio)", String(format: "%.2f s", result.audioSeconds))
                Metric("เวลาถอดเสียง (transcription)", String(format: "%.3f s", result.totalSeconds))
                Metric("  features / encoder / decoder", String(format: "%.3f / %.3f / %.3f", result.featureSeconds, result.encoderSeconds, result.decoderSeconds))
                Metric("Real-time factor", String(format: "%.3f", result.realTimeFactor))
            }
            if let load = model.loadReport {
                Metric("โหลดโมเดล (load, \(model.loadedThreads ?? 0) threads)", String(format: "%.2f s", load.seconds))
                Metric("available memory before", load.availableBefore.megabytes)
                Metric("available memory after", load.availableAfter.megabytes)
                Metric("footprint before → after", "\(load.footprintBefore.megabytes) → \(load.footprintAfter.megabytes)")
            }
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospacedDigit())
        }
    }
}

extension SessionState {
    var summary: String {
        switch self {
        case .off: "off"
        case .idle(let expiresAt): "idle until \(expiresAt.formatted(date: .omitted, time: .standard))"
        case .listening(_, let language): "listening (\(language.rawValue))"
        case .transcribing: "transcribing"
        case .done(_, let text): "done: \(text)"
        case .failed(_, let reason): "failed: \(reason)"
        }
    }

    var isBusy: Bool {
        switch self {
        case .listening, .transcribing: true
        default: false
        }
    }
}

extension ModelState {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

extension UInt64 {
    var megabytes: String { String(format: "%.0f MB", Double(self) / 1_048_576) }
}

extension Optional where Wrapped == UInt64 {
    var megabytes: String { map(\.megabytes) ?? "n/a (iOS device only)" }
}
