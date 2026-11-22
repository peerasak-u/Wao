import SwiftUI
import WaoCore

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let globe: () -> UIView?

    var body: some View {
        ZStack {
            switch model.mode {
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

/// ✕ / waveform / ✓ over what has been heard so far, in the style of the reference screenshot.
private struct DictationView: View {
    @ObservedObject var model: KeyboardModel
    let dictation: KeyboardMode.Dictation

    /// The words sit on top where the eye rests; the controls sit at the bottom, within reach of the thumb.
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let heard = dictation.heard, !heard.text.isEmpty {
                    HeardText(heard: heard, settled: false)
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
        case .queued, .starting: "กำลังเริ่ม..."
        case .listening: "กำลังฟัง..."
        }
    }
}
