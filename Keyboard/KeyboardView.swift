import SwiftUI
import WaoCore

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let globe: () -> UIView?

    var body: some View {
        ZStack {
            Color(.systemGray5).ignoresSafeArea()
            switch model.mode {
            case .voice:
                VoiceView(model: model, globe: globe)
            case .typing:
                TypingView(model: model, globe: globe)
            case .dictation(let dictation):
                DictationView(model: model, dictation: dictation)
            }
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                // Floats over the top of the keyboard: its height is fixed, so a notice in the stack pushed keys out.
                Text(notice)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(.systemYellow).opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                    .padding(4)
                    .onTapGesture { model.notice = nil }
            }
        }
    }
}

private struct VoiceView: View {
    @ObservedObject var model: KeyboardModel
    let globe: () -> UIView?

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Button(action: model.micTapped) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .frame(width: 112, height: 112)
                    .foregroundStyle(Color(.systemBackground))
                    .background(Color(.label), in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dictation")
            Text("แตะเพื่อพูด")
                .font(.system(size: 15))
                .foregroundStyle(Color(.secondaryLabel))
            Spacer()
            HStack(spacing: 4) {
                if model.showsGlobe {
                    GlobeKey(make: globe).frame(width: 40)
                }
                SpecialKey(systemImage: "keyboard") { model.showTyping() }
                    .frame(width: 52)
                    .accessibilityLabel("Keyboard")
                KeyCap(label: KeyboardLayout.thai.spaceLabel) { model.insert(" ") }
                SpecialKey(systemImage: "delete.left") { model.deleteBackward() }
                    .frame(width: 52)
                SpecialKey(systemImage: "return") { model.insert("\n") }
                    .frame(width: 64)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 6)
    }
}

private struct TypingView: View {
    @ObservedObject var model: KeyboardModel
    let globe: () -> UIView?

    var body: some View {
        VStack(spacing: 8) {
            let rows = model.layout.rows
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    if index == rows.count - 1 {
                        SpecialKey(systemImage: model.shifted ? "shift.fill" : "shift") { model.shifted.toggle() }
                    }
                    ForEach(rows[index].indices, id: \.self) { column in
                        let key = rows[index][column]
                        KeyCap(label: key.text(shifted: model.shifted)) { model.type(key) }
                    }
                    if index == rows.count - 1 {
                        SpecialKey(systemImage: "delete.left") { model.deleteBackward() }
                    }
                }
            }
            HStack(spacing: 4) {
                if model.showsGlobe {
                    GlobeKey(make: globe).frame(width: 40)
                }
                SpecialKey(title: model.layout.switchLabel) { model.layout = model.layout.other }
                    .frame(width: 52)
                SpecialKey(systemImage: "mic.fill") { model.showVoice() }
                    .frame(width: 44)
                    .accessibilityLabel("Voice")
                KeyCap(label: model.layout.spaceLabel) { model.insert(" ") }
                SpecialKey(systemImage: "return") { model.insert("\n") }
                    .frame(width: 64)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 6)
    }
}

private struct KeyCap: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 19))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(Color(.label))
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct SpecialKey: View {
    var title: String?
    var systemImage: String?
    let action: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    init(systemImage: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage { Image(systemName: systemImage) } else { Text(title ?? "").font(.system(size: 15)) }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(Color(.label))
            .background(Color(.systemGray3), in: RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// The globe has to be a UIKit control so `handleInputModeList(from:with:)` gets real touch events.
private struct GlobeKey: UIViewRepresentable {
    let make: () -> UIView?

    func makeUIView(context: Context) -> UIView {
        let view = make() ?? UIView()
        view.backgroundColor = .systemGray3
        view.layer.cornerRadius = 5
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// ✕ / waveform / ✓ over what has been heard so far, in the style of the reference screenshot.
private struct DictationView: View {
    @ObservedObject var model: KeyboardModel
    let dictation: KeyboardMode.Dictation

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: model.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(Color(.label))
                        .background(Color(.systemBackground), in: Circle())
                }
                .accessibilityLabel("Cancel")
                Spacer()
                Waveform(levels: model.levels, active: isListening)
                    .frame(height: 48)
                Spacer()
                Button(action: model.confirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.white)
                        .background(Color(.label), in: Circle())
                }
                .disabled(!isListening)
                .opacity(isListening ? 1 : 0.4)
                .accessibilityLabel("Done")
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            Spacer(minLength: 12)
            if let heard = dictation.heard, !heard.text.isEmpty {
                HeardText(heard: heard, settled: !isListening)
                    .padding(.horizontal, 20)
            } else {
                HStack(spacing: 8) {
                    if !isListening { ProgressView() }
                    Text(caption)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            Spacer(minLength: 12)
        }
    }

    private var isListening: Bool { dictation.phase == .listening }

    private var caption: String {
        switch dictation.phase {
        case .starting: "กำลังเริ่ม..."
        case .listening: "กำลังฟัง..."
        case .transcribing: "กำลังถอดเสียง..."
        }
    }
}

/// The newest three lines of the preview: the text is bottom-aligned in a fixed frame and its start is clipped
/// off the top, so the words being spoken stay in view.
private struct HeardText: View {
    static let lineHeight: CGFloat = 30

    let heard: Heard
    let settled: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text((heard.clipped ? "…" : "") + heard.text)
                .font(.system(size: 20))
                .foregroundStyle(Color(.label).opacity(settled ? 0.4 : 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: Self.lineHeight * 3, alignment: .bottom)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25)],
                                     startPoint: .top, endPoint: .bottom))
            if settled { ProgressView() }
        }
        .animation(.easeOut(duration: 0.15), value: heard)
    }
}

private struct Waveform: View {
    let levels: [Float]
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(Color(.label).opacity(active ? 0.85 : 0.3))
                    .frame(width: 3, height: 4 + CGFloat(levels[i]) * 40)
            }
        }
        .animation(.linear(duration: 0.05), value: levels)
    }
}
