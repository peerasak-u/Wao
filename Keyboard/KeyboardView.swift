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
            HStack(spacing: 0) {
                if model.showsGlobe {
                    GlobeKey(make: globe).padded().frame(width: 46)
                }
                SpecialKey(systemImage: "keyboard", action: model.showTyping)
                    .frame(width: 52)
                    .accessibilityLabel("Keyboard")
                KeyCap(label: "เว้นวรรค") { model.insert(" ") }
                DeleteKey(action: model.deleteBackward)
                    .frame(width: 56)
                SpecialKey(systemImage: "return") { model.insert("\n") }
                    .frame(width: 68)
            }
            .frame(height: Key.capHeight + Key.gap.height)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
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
