import Combine
import SwiftUI
import WaoCore
import WaoInference

@main
struct WaoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        let title: [NSAttributedString.Key: Any] = [.font: UIFont(name: "SukhumvitSet-SemiBold", size: 17)!, .foregroundColor: UIColor.white]
        bar.titleTextAttributes = title
        bar.largeTitleTextAttributes = [.font: UIFont(name: "SukhumvitSet-Bold", size: 32)!, .foregroundColor: UIColor.white]
        bar.backButtonAppearance.normal.titleTextAttributes = [.font: UIFont(name: "SukhumvitSet-Text", size: 17)!]
        let scrolled = bar.copy()
        scrolled.backgroundColor = UIColor(white: 0.039, alpha: 0.92)
        scrolled.shadowColor = UIColor(white: 1, alpha: 0.08)
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().tintColor = .white
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "wao", url.host == "session" else { return }
                    Task { await model.beginSession() }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .background { model.commitVocabularyNow() } }
        }
    }
}

enum Palette {
    static let canvas = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.35)
    static let hairline = Color.white.opacity(0.08)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            main
                .navigationTitle("เว่า")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: VocabularyRoute.self) { $0.screen }
                .navigationDestination(for: CreditsRoute.self) { $0.screen }
        }
        .alert("เกิดข้อผิดพลาด", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("ตกลง") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var main: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 32) {
                    Hero { withAnimation(.snappy) { proxy.scrollTo(SetupCard.anchor, anchor: .top) } }
                    SessionCard()
                    SetupCard().id(SetupCard.anchor)
                    VocabularyCard()
                    CreditsFooter()
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .overlay {
            GeometryReader { geometry in
                let inset = geometry.safeAreaInsets.top
                LinearGradient(stops: [
                    .init(color: Palette.canvas, location: 0),
                    .init(color: Palette.canvas, location: inset / (inset + 28)),
                    .init(color: Palette.canvas.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: inset + 28)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)
        }
        .screenBackground()
    }
}

extension View {
    func screenBackground() -> some View {
        font(.loopless(16))
            .foregroundStyle(.white)
            .background {
                ZStack(alignment: .top) {
                    Palette.canvas
                    RadialGradient(colors: [.white.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 300)
                        .frame(width: 640, height: 640)
                        .offset(y: -200)
                }
                .ignoresSafeArea()
            }
    }
}

private struct Hero: View {
    let showSetup: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("เว่า")
                .font(.loopless(72, .bold))
                .shadow(color: .white.opacity(0.25), radius: 24)
            Text("พูดไทยปนอังกฤษ พิมพ์ได้ทุกแอป\nถอดเสียงบนเครื่อง ไม่ส่งเสียงออกนอกเครื่อง")
                .font(.loopless(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondary)
                .lineSpacing(2)
            TestPanel(showSetup: showSetup)
                .padding(.top, 18)
        }
    }
}

/// The hero waveform is the test button: tap, speak, tap, and read what the model heard.
private struct TestPanel: View {
    @EnvironmentObject private var model: AppModel
    let showSetup: () -> Void

    private var blocker: (reason: String, step: Int?)? {
        if !model.model.isReady { return ("ต้องดาวน์โหลดโมเดลก่อน", 1) }
        if model.micPermission != .granted { return ("ต้องอนุญาตไมโครโฟนก่อน", 2) }
        switch model.test {
        case .ready, .done: if model.session.isBusy { return ("คีย์บอร์ดกำลังใช้ไมค์อยู่", nil) }
        case .recording, .transcribing: break
        }
        return nil
    }

    private var look: TestWaveform.Look {
        switch model.test {
        case .recording: .live
        case .transcribing: .shimmer
        case .ready, .done: .breathing
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Button { Task { await model.toggleTest() } } label: {
                TestWaveform(look: look).frame(height: 72)
            }
            .buttonStyle(Pressable(scale: 0.94))
            .disabled(blocker != nil || model.isLoading || model.test.isTranscribing)
            .opacity(blocker != nil ? 0.35 : 1)
            .accessibilityLabel(model.test.isRecording ? "หยุดและถอดเสียง" : "ลองพูด")
            .accessibilityIdentifier("mic-test")
            caption
                .font(.loopless(14))
                .foregroundStyle(Palette.secondary)
            output
                .transition(.opacity)
        }
        .animation(.snappy, value: model.test.step)
        .sensoryFeedback(trigger: model.test.step) { _, step in
            switch step {
            case .recording: .start
            case .transcribing: .stop
            case .done: .success
            case .ready: nil
            }
        }
    }

    @ViewBuilder private var caption: some View {
        if let blocker {
            HStack(spacing: 6) {
                Text(blocker.reason)
                if let step = blocker.step {
                    Button("ไปที่ขั้นที่ \(step)", action: showSetup)
                        .font(.loopless(14, .medium))
                        .foregroundStyle(.white)
                        .underline()
                }
            }
        } else {
            switch model.test {
            case .ready:
                Text(model.isLoading ? "กำลังโหลดโมเดล…" : "แตะเพื่อลองพูด")
            case .done:
                Text("แตะเพื่อลองอีกครั้ง")
            case .recording(let since, _):
                HStack(spacing: 8) {
                    LiveDot()
                    Text("กำลังฟัง · แตะเพื่อหยุด")
                    Text(since, style: .timer)
                        .font(.loopless(14, .medium).monospacedDigit())
                        .foregroundStyle(.white)
                }
            case .transcribing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("กำลังถอดเสียง")
                }
            }
        }
    }

    @ViewBuilder private var output: some View {
        switch model.test {
        case .ready:
            EmptyView()
        case .recording(_, let heard), .transcribing(let heard):
            Group {
                if let heard, !heard.text.isEmpty {
                    HeardText(heard: heard, settled: model.test.isTranscribing)
                } else {
                    Text(model.test.isTranscribing ? "" : "พูดได้เลย…")
                        .font(.loopless(HeardText.size, .medium))
                        .foregroundStyle(Palette.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(height: HeardText.lineHeight * 3)
            .padding(18)
            .card()
        case .done(let result):
            TestResult(result: result)
        }
    }
}

private struct TestResult: View {
    let result: Transcription
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(result.text.isEmpty ? "(ไม่ได้ยินเสียงพูด)" : result.text)
                .font(.loopless(24, .medium))
                .foregroundStyle(result.text.isEmpty ? Palette.tertiary : .white)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("result-text")
            HStack {
                Text(String(format: "%.1f วินาที · ถอดใน %.2f วินาที", result.audioSeconds, result.totalSeconds))
                    .font(.loopless(13).monospacedDigit())
                    .foregroundStyle(Palette.tertiary)
                Spacer()
                Button {
                    UIPasteboard.general.string = result.text
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "คัดลอกแล้ว" : "คัดลอก", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.loopless(13, .medium))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(Pressable())
                .disabled(result.text.isEmpty)
                .sensoryFeedback(.success, trigger: copied) { _, now in now }
            }
        }
        .padding(18)
        .card()
    }
}

private struct LiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 7, height: 7)
            .shadow(color: .white.opacity(0.9), radius: 5)
            .opacity(pulse ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(), value: pulse)
            .onAppear { pulse = true }
    }
}

/// Live from the bridge while recording; otherwise a sine fed through the same rolling buffer, so it ripples
/// outward from the centre the way speech does: a slow breath at rest, a quick low shimmer while transcribing.
private struct TestWaveform: View {
    enum Look { case breathing, live, shimmer }

    let look: Look
    @State private var levels = Array(repeating: Float(0), count: Waveform.barsPerSide + 1)
    @State private var bridge = try? Bridge.shared()
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        Waveform(levels: levels, active: true, lit: look == .live)
            .animation(.easeOut(duration: 0.3), value: look)
            .onReceive(tick) { now in
                levels = Array(levels.dropFirst()) + [nextLevel(at: now)]
            }
    }

    private func nextLevel(at now: Date) -> Float {
        let t = now.timeIntervalSinceReferenceDate
        switch look {
        case .live: return bridge?.readLevel() ?? 0
        case .shimmer: return Float(0.16 + 0.1 * sin(t * 2 * .pi / 0.9))
        case .breathing: return Float(0.3 + 0.22 * sin(t * 2 * .pi / 3.2))
        }
    }
}

private struct SessionCard: View {
    @EnvironmentObject private var model: AppModel

    private var on: Bool { model.isKeyboardSessionOn }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? .white : Palette.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("เซสชันคีย์บอร์ด").font(.loopless(16, .medium))
                Text(model.model.isReady || on ? "เปิดไมค์ค้างไว้ให้คีย์บอร์ดใช้ในแอปอื่น" : "ต้องดาวน์โหลดโมเดลก่อน จึงจะเปิดได้")
                    .font(.loopless(13))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if on {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(.white)
                                .frame(width: 6, height: 6)
                                .shadow(color: .white.opacity(0.8), radius: 4)
                            Text(status(at: context.date))
                                .font(.loopless(13, .medium).monospacedDigit())
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PillButton(title: on ? "ปิด" : "เปิด", prominent: !on) {
                Task { on ? await model.endSession() : await model.beginSession() }
            }
            .disabled(!on && !model.model.isReady)
            .opacity(!on && !model.model.isReady ? 0.35 : 1)
            .accessibilityIdentifier("session-toggle")
        }
        .padding(18)
        .card(lit: on)
        .animation(.snappy, value: on)
    }

    private func status(at now: Date) -> String {
        switch model.session {
        case .idle(let expiresAt):
            let seconds = max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
            return "พร้อมฟัง · ปิดเองใน \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        case .listening:
            return model.test.isRecording ? "ไมค์ใช้ทดสอบอยู่" : "กำลังฟังจากคีย์บอร์ด"
        case .transcribing:
            return "กำลังถอดเสียง"
        case .off, .done, .failed:
            return "พร้อมฟัง"
        }
    }
}

private struct SetupCard: View {
    static let anchor = "setup"

    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardReady = false
    @State private var expanded = false

    private var micReady: Bool { model.micPermission == .granted }
    private var allDone: Bool { model.model.isReady && micReady && keyboardReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if allDone && !expanded {
                Button { withAnimation(.snappy) { expanded = true } } label: {
                    HStack(spacing: 14) {
                        StepMark(done: true, number: 0)
                        Text("ตั้งค่าครบแล้ว").font(.loopless(16, .medium))
                        Spacer()
                        Text("ใช้ได้ทุกแอป").font(.loopless(14)).foregroundStyle(Palette.tertiary)
                    }
                    .padding(18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("ตั้งค่า")
                    .font(.loopless(13, .medium))
                    .foregroundStyle(Palette.tertiary)
                    .padding([.horizontal, .top], 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if allDone { withAnimation(.snappy) { expanded = false } } }
                modelStep
                Divider().overlay(Palette.hairline).padding(.leading, 60)
                micStep
                Divider().overlay(Palette.hairline).padding(.leading, 60)
                keyboardStep
            }
        }
        .card()
        .onAppear(perform: refreshKeyboard)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshKeyboard() } }
        .onChange(of: model.session) { _, _ in refreshKeyboard() }
    }

    /// Only a keyboard with Full Access can write to the App Group, so any command on file proves both.
    private func refreshKeyboard() {
        keyboardReady = ((try? Bridge.shared().readCommand()) ?? nil) != nil
    }

    @ViewBuilder private var modelStep: some View {
        Step(number: 1, done: model.model.isReady, title: "โมเดลถอดเสียง", detail: modelDetail) {
            switch model.model {
            case .missing: PillButton(title: "ดาวน์โหลด", action: model.download)
            case .downloading: PillButton(title: "หยุด", action: model.pauseDownload)
            case .paused: PillButton(title: "ดาวน์โหลดต่อ", action: model.download)
            case .failed: PillButton(title: "ลองอีกครั้ง", action: model.download)
            case .ready: EmptyView()
            }
        } footer: {
            switch model.model {
            case .missing:
                Text("แนะนำให้ต่อ Wi-Fi · ดาวน์โหลดครั้งเดียว")
                    .font(.loopless(13))
                    .foregroundStyle(Palette.tertiary)
            case .downloading(let progress), .paused(let progress):
                ProgressBar(value: progress.fraction)
            case .failed(_, let progress) where progress.received > 0:
                ProgressBar(value: progress.fraction)
            default:
                EmptyView()
            }
        }
    }

    private var modelDetail: String {
        switch model.model {
        case .missing: "OpenThai2.0 ASR โดย iApp Technology · ประมาณ 1 GB"
        case .downloading(let progress): "กำลังดาวน์โหลด · \(progress.megabytes)"
        case .paused(let progress): "หยุดไว้ · \(progress.megabytes)"
        case .ready: "OpenThai2.0 ASR โดย iApp Technology\nพร้อมใช้บนเครื่อง"
        case .failed(let reason, let progress): progress.received > 0 ? "\(reason)\n\(progress.megabytes)" : reason
        }
    }

    private var micStep: some View {
        Step(number: 2, done: micReady, title: "ไมโครโฟน", detail: micDetail) {
            switch model.micPermission {
            case .granted: EmptyView()
            case .denied: PillButton(title: "เปิดการตั้งค่า", action: openSettings)
            default: PillButton(title: "อนุญาต") { Task { await model.requestMicrophone() } }
            }
        }
    }

    private var micDetail: String {
        switch model.micPermission {
        case .granted: "อนุญาตแล้ว"
        case .denied: "ถูกปฏิเสธ เปิดได้ในการตั้งค่า"
        default: "ใช้ฟังเสียงพูดบนเครื่องนี้เท่านั้น"
        }
    }

    private var keyboardStep: some View {
        Step(
            number: 3, done: keyboardReady, title: "แป้นพิมพ์และการเข้าถึงแบบเต็ม",
            detail: keyboardReady
                ? "แป้นพิมพ์เว่าเชื่อมต่อแล้ว"
                : "ทั่วไป › แป้นพิมพ์ › เพิ่มแป้นพิมพ์ใหม่ › เว่า แล้วเปิดอนุญาตการเข้าถึงแบบเต็ม"
        ) {
            if !keyboardReady { PillButton(title: "เปิดการตั้งค่า", action: openSettings) }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

private struct Step<Action: View, Footer: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder let action: Action
    @ViewBuilder let footer: Footer

    init(number: Int, done: Bool, title: String, detail: String,
         @ViewBuilder action: () -> Action, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.number = number
        self.done = done
        self.title = title
        self.detail = detail
        self.action = action()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                StepMark(done: done, number: number)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.loopless(16, .medium))
                    Text(detail)
                        .font(.loopless(13))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                action
            }
            // Below the action, so the progress bar keeps one width whichever button sits beside it.
            footer.padding(.leading, 28 + 14)
        }
        .padding(18)
    }
}

private struct StepMark: View {
    let done: Bool
    let number: Int

    var body: some View {
        ZStack {
            if done {
                Circle().fill(.white).shadow(color: .white.opacity(0.4), radius: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.canvas)
            } else {
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                Text("\(number)")
                    .font(.loopless(13, .medium))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(width: 28, height: 28)
    }
}

struct PillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.loopless(14, prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? Palette.canvas : .white)
                .padding(.horizontal, prominent ? 18 : 14)
                .frame(minHeight: 32)
                .background {
                    if prominent {
                        Capsule().fill(.white).shadow(color: .white.opacity(0.3), radius: 10)
                    } else {
                        Capsule().fill(.white.opacity(0.1))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    }
                }
        }
        .buttonStyle(Pressable())
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(.white)
                    .frame(width: geometry.size.width * value)
                    .shadow(color: .white.opacity(0.5), radius: 4)
            }
        }
        .frame(height: 4)
        .animation(.easeOut, value: value)
    }
}

struct Pressable: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func card(lit: Bool = false) -> some View {
        background(.white.opacity(lit ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(lit ? .white.opacity(0.2) : Palette.hairline, lineWidth: 1))
    }
}

extension SessionState {
    var isBusy: Bool {
        switch self {
        case .listening, .transcribing: true
        default: false
        }
    }
}

extension DownloadProgress {
    var megabytes: String { "\(received / 1_000_000) / \(total / 1_000_000) MB" }
}

extension ModelState {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
