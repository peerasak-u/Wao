import Combine
import SwiftUI
import WaoCore
import WaoInference

@main
struct WaoApp: App {
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
        }
        .alert("เกิดข้อผิดพลาด", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("ตกลง") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var main: some View {
        ScrollView {
            VStack(spacing: 32) {
                Hero()
                PrimaryAction()
                SetupCard()
                VocabularyCard()
                LabCard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 40)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
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
            HeroWaveform()
                .frame(height: 64)
                .padding(.top, 18)
        }
    }
}

/// Live from the bridge while listening; otherwise a slow sine fed through the same rolling buffer, so the
/// breath ripples outward from the centre the way speech does.
private struct HeroWaveform: View {
    @EnvironmentObject private var model: AppModel
    @State private var levels = Array(repeating: Float(0), count: Waveform.barsPerSide + 1)
    @State private var bridge = try? Bridge.shared()
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        Waveform(levels: levels, active: true)
            .onReceive(tick) { now in
                levels = Array(levels.dropFirst()) + [nextLevel(at: now)]
            }
    }

    private func nextLevel(at now: Date) -> Float {
        if case .listening = model.session { return bridge?.readLevel() ?? 0 }
        let phase = now.timeIntervalSinceReferenceDate * 2 * .pi / 3.2
        return Float(0.3 + 0.22 * sin(phase))
    }
}

private struct PrimaryAction: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Button {
                Task { model.isSessionLive ? await model.endSession() : await model.beginSession() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.isSessionLive ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                    Text(model.isSessionLive ? "ปิดเซสชัน" : "เริ่มเซสชัน")
                        .font(.loopless(19, .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .foregroundStyle(model.isSessionLive ? .white : Palette.canvas)
                .background {
                    if model.isSessionLive {
                        Capsule().fill(.white.opacity(0.06))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    } else {
                        Capsule().fill(.white)
                            .shadow(color: .white.opacity(0.35), radius: 22)
                    }
                }
            }
            .buttonStyle(Pressable())
            .disabled(!model.isSessionLive && !model.model.isReady)
            .opacity(!model.isSessionLive && !model.model.isReady ? 0.35 : 1)
            SessionStatus()
        }
    }
}

private struct SessionStatus: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                Circle()
                    .fill(model.isSessionLive ? Color.white : Palette.tertiary)
                    .frame(width: 6, height: 6)
                    .shadow(color: .white.opacity(model.isSessionLive ? 0.8 : 0), radius: 4)
                Text(text(at: context.date))
                    .font(.loopless(14).monospacedDigit())
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    private func text(at now: Date) -> String {
        guard model.model.isReady || model.isSessionLive else { return "ต้องดาวน์โหลดโมเดลก่อน จึงจะเริ่มได้" }
        switch model.session {
        case .off:
            return "ปิดอยู่ · ไมโครโฟนปิดเองหลังไม่ใช้ 5 นาที"
        case .idle(let expiresAt):
            let seconds = max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
            return "พร้อมฟัง · ปิดเองใน \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        case .listening:
            return "กำลังฟัง"
        case .transcribing:
            return "กำลังถอดเสียง"
        case .done:
            return "ถอดเสียงเสร็จแล้ว"
        case .failed(_, let reason):
            return "ถอดเสียงไม่สำเร็จ · \(reason)"
        }
    }
}

private struct SetupCard: View {
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
            case .missing: PillButton(title: "ดาวน์โหลด") { Task { await model.download() } }
            case .failed: PillButton(title: "ลองอีกครั้ง") { Task { await model.download() } }
            case .downloading, .ready: EmptyView()
            }
        } footer: {
            if case .downloading(let progress) = model.model {
                ProgressBar(value: progress)
            }
        }
    }

    private var modelDetail: String {
        switch model.model {
        case .missing: "OpenThai2.0 ASR · ประมาณ 1 GB"
        case .downloading(let progress): "กำลังดาวน์โหลด \(Int(progress * 100))%"
        case .ready: "พร้อมใช้บนเครื่อง"
        case .failed(let reason): reason
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
        HStack(alignment: .top, spacing: 14) {
            StepMark(done: done, number: number)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.loopless(16, .medium))
                Text(detail)
                    .font(.loopless(13))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                footer.padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.loopless(14, .medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(.white.opacity(0.1), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
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

private struct LabCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var expanded = false
    @State private var language = Language.thai

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack {
                    Image(systemName: "flask")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 28)
                    Text("ห้องทดลอง").font(.loopless(16, .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                content
                    .padding([.horizontal, .bottom], 18)
                    .transition(.opacity)
            }
        }
        .card()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabRow("ภาษา") {
                Picker("ภาษา", selection: $language) {
                    Text("ไทย").tag(Language.thai)
                    Text("ไทย+อังกฤษ").tag(Language.thaiEnglishMix)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            LabRow("CPU threads") {
                Picker("CPU threads", selection: $model.threads) {
                    ForEach([1, 2, 4], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            if let result = model.lastResult {
                Text(result.text.isEmpty ? "(ว่าง)" : result.text)
                    .font(.loopless(19, .medium))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("result-text")
                VStack(spacing: 8) {
                    Metric("ความยาวเสียง", String(format: "%.2f s", result.audioSeconds))
                    Metric("เวลาถอดเสียง", String(format: "%.3f s", result.totalSeconds))
                    Metric("features / encoder / decoder", String(format: "%.3f / %.3f / %.3f", result.featureSeconds, result.encoderSeconds, result.decoderSeconds))
                    Metric("Real-time factor", String(format: "%.3f", result.realTimeFactor))
                }
            }
            if let load = model.loadReport {
                VStack(spacing: 8) {
                    Metric("โหลดโมเดล (\(model.loadedThreads ?? 0) threads)", String(format: "%.2f s", load.seconds))
                    Metric("หน่วยความจำว่าง ก่อนโหลด", load.availableBefore.megabytes)
                    Metric("หน่วยความจำว่าง หลังโหลด", load.availableAfter.megabytes)
                    Metric("footprint ก่อน → หลัง", "\(load.footprintBefore.megabytes) → \(load.footprintAfter.megabytes)")
                }
            }
        }
    }
}

private struct LabRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title).font(.loopless(14)).foregroundStyle(Palette.secondary)
            Spacer()
            control
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
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.loopless(13)).foregroundStyle(Palette.secondary)
            Spacer()
            Text(value)
                .font(.loopless(13).monospacedDigit())
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}

struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func card() -> some View {
        background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
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
    var megabytes: String { map(\.megabytes) ?? "ไม่มี (เฉพาะเครื่องจริง)" }
}
