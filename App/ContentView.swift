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
        bar.titleTextAttributes = [.font: InkFont.ui(17, .semibold, fallback: .semibold), .foregroundColor: Palette.UI.ink]
        bar.largeTitleTextAttributes = [.font: InkFont.ui(32, .bold, fallback: .bold), .foregroundColor: Palette.UI.ink]
        bar.backButtonAppearance.normal.titleTextAttributes = [.font: InkFont.ui(17)]
        let scrolled = bar.copy()
        scrolled.backgroundColor = Palette.UI.canvas(0.92)
        scrolled.shadowColor = Palette.UI.hairline
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().tintColor = Palette.UI.ink
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    guard url.scheme == "wao", url.host == "session" else { return }
                    Task { await model.beginSession() }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .background { model.commitVocabularyNow() } }
        }
    }
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
                    HapticsCard()
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

private struct Hero: View {
    let showSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                Wordmark(size: 80)
                HandNote(pointing: .upLeft) {
                    Text("ขีดนี้แหละ\nพระเอก")
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
            Text("พูดไทยปนอังกฤษ พิมพ์ได้ทุกแอป\nถอดเสียงบนเครื่อง ไม่ส่งเสียงออกนอกเครื่อง")
                .font(.ink(15))
                .multilineTextAlignment(.leading)
                .foregroundStyle(Palette.secondary)
                .lineSpacing(2)
            TestPanel(showSetup: showSetup)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The ring is the test button: tap, speak, tap, and read what the model heard.
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

    private var look: StrokeWave.Look {
        switch model.test {
        case .recording: .live
        case .transcribing: .shimmer
        case .ready, .done: .breathing
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button { Task { await model.toggleTest() } } label: {
                    ZStack {
                        Circle().strokeBorder(Palette.ink, lineWidth: 1.5)
                        StrokeWave(look: look)
                    }
                    .frame(width: 112, height: 112)
                    .contentShape(Circle())
                }
                .buttonStyle(Pressable(scale: 0.94))
                .disabled(blocker != nil || model.isLoading || model.test.isTranscribing)
                .opacity(blocker != nil ? 0.35 : 1)
                .accessibilityLabel(model.test.isRecording ? "หยุดและถอดเสียง" : "ลองพูด")
                .accessibilityIdentifier("mic-test")
                HandNote(pointing: .left) {
                    caption
                }
                Spacer(minLength: 0)
            }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(blocker.reason)
                if let step = blocker.step {
                    Button("ไปที่ขั้นที่ \(step)", action: showSetup)
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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        LiveDot()
                        Text(since, style: .timer)
                            .font(.hand(17).monospacedDigit())
                    }
                    Text("กำลังฟัง · แตะเพื่อหยุด")
                }
            case .transcribing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Palette.ink)
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
                    HeardText(heard: heard, settled: model.test.isTranscribing, fontName: InkFont.medium)
                } else {
                    Text(model.test.isTranscribing ? "" : "พูดได้เลย…")
                        .font(.ink(HeardText.size, .medium))
                        .foregroundStyle(Palette.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(height: HeardText.lineHeight(fontName: InkFont.medium) * 3)
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
                .font(.ink(24, .medium))
                .foregroundStyle(result.text.isEmpty ? Palette.tertiary : Palette.ink)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("result-text")
            HStack {
                Text(String(format: "%.1f วินาที · ถอดใน %.2f วินาที", result.audioSeconds, result.totalSeconds))
                    .font(.ink(13).monospacedDigit())
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
                        .font(.ink(13, .medium))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .pill(prominent: false)
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
            .fill(Palette.ink)
            .frame(width: 7, height: 7)
            .opacity(pulse ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(), value: pulse)
            .onAppear { pulse = true }
    }
}

/// One ไม้เอก at rest; while recording it multiplies into a waveform fed live from the bridge, newest level in the
/// centre spreading outwards; while transcribing a low sine runs through the same rolling buffer.
private struct StrokeWave: View {
    enum Look { case breathing, live, shimmer }

    private static let perSide = 3

    let look: Look
    @State private var levels = Array(repeating: Float(0), count: perSide + 1)
    @State private var bridge = try? Bridge.shared()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 4) {
            ForEach(-Self.perSide...Self.perSide, id: \.self) { i in
                let hidden = look == .breathing && i != 0
                Image(decorative: "MaiEk")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: hidden ? 0 : height(abs(i)))
                    .opacity(hidden ? 0 : 1)
            }
        }
        .foregroundStyle(Palette.ink)
        .animation(.easeOut(duration: 0.08), value: levels)
        .animation(.snappy, value: look)
        // The app stays alive in the background through every dictation, where nobody sees this.
        .task(id: scenePhase == .active ? look : nil) {
            guard scenePhase == .active, look != .breathing else { return }
            while !Task.isCancelled {
                levels = Array(levels.dropFirst()) + [nextLevel(at: Date())]
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func height(_ age: Int) -> CGFloat {
        let level = CGFloat(levels[levels.count - 1 - age])
        switch look {
        case .breathing: return 56
        case .shimmer: return 12 + level * 12
        case .live:
            let falloff = 1 - CGFloat(age) / CGFloat(Self.perSide + 1)
            return 12 + level * 40 * falloff * falloff
        }
    }

    private func nextLevel(at now: Date) -> Float {
        switch look {
        case .live: bridge?.readLevel() ?? 0
        case .shimmer: Float(0.16 + 0.1 * sin(now.timeIntervalSinceReferenceDate * 2 * .pi / 0.9))
        case .breathing: 0
        }
    }
}

private struct SessionCard: View {
    @EnvironmentObject private var model: AppModel

    private var on: Bool { model.isKeyboardSessionOn }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "keyboard")
                .font(.ink(15, .medium))
                .foregroundStyle(on ? Palette.ink : Palette.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("เซสชันคีย์บอร์ด").font(.ink(16, .medium))
                Text(model.model.isReady || on ? "เปิดไมค์ค้างไว้ให้คีย์บอร์ดใช้ในแอปอื่น" : "ต้องดาวน์โหลดโมเดลก่อน จึงจะเปิดได้")
                    .font(.ink(13))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if on {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Palette.ink)
                                .frame(width: 6, height: 6)
                            Text(status(at: context.date))
                                .font(.ink(13, .medium).monospacedDigit())
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

/// The keyboard reads this switch from the App Group each time it appears, and only with Full Access.
private struct HapticsCard: View {
    @AppStorage(KeyHaptics.key, store: KeyHaptics.store) private var on = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "hand.tap")
                .font(.ink(15, .medium))
                .foregroundStyle(on ? Palette.ink : Palette.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("สั่นเมื่อแตะแป้นและคำแนะนำ").font(.ink(16, .medium))
                Text("ต้องเปิดการเข้าถึงแบบเต็มให้คีย์บอร์ดเว่า")
                    .font(.ink(13))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("สั่นเมื่อแตะแป้นและคำแนะนำ", isOn: $on)
                .toggleStyle(InkSwitch())
                .labelsHidden()
                .accessibilityIdentifier("haptics-toggle")
        }
        .padding(18)
        .card()
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
                        Text("ตั้งค่าครบแล้ว").font(.ink(16, .medium))
                        Spacer()
                        Text("ใช้ได้ทุกแอป").font(.ink(14)).foregroundStyle(Palette.tertiary)
                    }
                    .padding(18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("ตั้งค่า")
                    .font(.ink(13, .medium))
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
                    .font(.ink(13))
                    .foregroundStyle(Palette.tertiary)
            case .downloading(let progress), .paused(let progress):
                StrokeProgress(value: progress.fraction)
            case .failed(_, let progress) where progress.received > 0:
                StrokeProgress(value: progress.fraction)
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
                    Text(title).font(.ink(16, .medium))
                    Text(detail)
                        .font(.ink(13))
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
                Circle().strokeBorder(Palette.ink, lineWidth: 1.5)
                Image("InkTick", label: Text("เสร็จแล้ว"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
            } else {
                Circle().strokeBorder(Palette.tertiary, lineWidth: 1.5)
                Text("\(number)")
                    .font(.ink(13, .medium))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(width: 28, height: 28)
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
