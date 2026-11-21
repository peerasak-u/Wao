import SwiftUI
import WaoCore

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let globe: () -> UIView?

    var body: some View {
        ZStack {
            switch model.mode {
            case .voice:
                VoiceView(model: model, globe: globe)
            case .dictation(let dictation):
                DictationView(model: model, dictation: dictation)
            }
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                // Floats over the top of the keyboard: its height is fixed, so a notice in the stack pushed keys out.
                Text(notice)
                    .font(.loopless(13))
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
                .font(.loopless(15))
                .foregroundStyle(Color(.secondaryLabel))
            Spacer()
            HStack(spacing: 4) {
                if model.showsGlobe {
                    GlobeKey(make: globe).frame(width: 40)
                }
                KeyCap(label: "เว้นวรรค") { model.insert(" ") }
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

private struct KeyCap: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.loopless(17))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(Color(.label))
                .background(Color(.systemGray4), in: RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct SpecialKey: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
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

    /// The words sit on top where the eye rests; the controls sit at the bottom, within reach of the thumb.
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let heard = dictation.heard, !heard.text.isEmpty {
                    HeardText(heard: heard, settled: !isListening)
                } else {
                    HStack(spacing: 8) {
                        if !isListening { ProgressView() }
                        Text(caption)
                            .font(.loopless(17, .medium))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: HeardText.lineHeight * 3)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            Spacer(minLength: 8)
            HStack {
                Button(action: model.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 56, height: 56)
                        .foregroundStyle(Color(.label))
                        .background(Color(.systemGray4), in: Circle())
                }
                .accessibilityLabel("Cancel")
                Spacer()
                Waveform(levels: model.levels, active: isListening)
                    .frame(height: 56)
                Spacer()
                Button(action: model.confirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 56, height: 56)
                        .foregroundStyle(Color(.systemBackground))
                        .background(Color(.label), in: Circle())
                }
                .disabled(!isListening)
                .opacity(isListening ? 1 : 0.4)
                .accessibilityLabel("Done")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
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

/// The preview from the top of its box; once it runs past three lines its start is clipped off the top, so the
/// words being spoken stay in view.
private struct HeardText: View {
    static let size: CGFloat = 21
    /// Sukhumvit Set's lines are taller than the system font's; a box sized for those cut the top line in half.
    static let lineHeight = UIFont(name: "SukhumvitSet-Medium", size: size)?.lineHeight ?? 36

    let heard: Heard
    let settled: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text((heard.clipped ? "…" : "") + heard.text)
                .font(.loopless(Self.size, .medium))
                .foregroundStyle(Color(.label).opacity(settled ? 0.4 : 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: Self.lineHeight * 3, alignment: .bottom)
                .clipped()
                .frame(maxHeight: .infinity, alignment: .top)
            if settled { ProgressView() }
        }
    }
}

/// Bars mirrored around the centre: the newest level sits in the middle and older ones move outwards, so each
/// sound spreads from the centre. Bars shrink and fade towards the edges, down to dots, under a glow that
/// follows the voice.
private struct Waveform: View {
    static let barsPerSide = 11

    let levels: [Float]
    let active: Bool

    var body: some View {
        let ink = Color(.label)
        let newest = CGFloat(active ? levels.last ?? 0 : 0)
        HStack(alignment: .center, spacing: 4) {
            ForEach(-Self.barsPerSide...Self.barsPerSide, id: \.self) { i in
                let falloff = 1 - CGFloat(abs(i)) / CGFloat(Self.barsPerSide + 1)
                Capsule()
                    .fill(LinearGradient(colors: [ink.opacity(0.75), ink, ink.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 5, height: 5 + level(abs(i)) * 38 * falloff * falloff)
                    .opacity(active ? 0.2 + 0.8 * falloff * falloff : 0.2)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .background {
            RadialGradient(colors: [ink.opacity(0.45 * newest), .clear], center: .center, startRadius: 0, endRadius: 60)
                .blur(radius: 10)
        }
        .background(ink.opacity(0.03))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(ink.opacity(0.12), lineWidth: 1))
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    /// The level `age` steps before the newest one.
    private func level(_ age: Int) -> CGFloat {
        guard active, age < levels.count else { return 0 }
        return CGFloat(levels[levels.count - 1 - age])
    }
}

private extension Font {
    enum Face: String { case text = "Text", medium = "Medium" }

    /// Sukhumvit Set ships with iOS and has no loops (หัว); the system's Thai fallback, Thonburi, does.
    static func loopless(_ size: CGFloat, _ face: Face = .text) -> Font {
        .custom("SukhumvitSet-\(face.rawValue)", size: size)
    }
}
