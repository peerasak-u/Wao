import SwiftUI
import UIKit

/// The click and the light tap a key gives when a finger lands on it, as on the system keyboard.
///
/// The click is `playInputClick()`, so iOS applies the user's keyboard sound setting. It has one sound, so delete
/// and the modifier keys click like letters. Haptics are skipped without Full Access. A keyboard cannot read the
/// system's haptics switch, so the app keeps its own (`KeyHaptics`).
@MainActor
final class KeyFeedback {
    static let shared = KeyFeedback()

    private var haptics: UIImpactFeedbackGenerator?

    /// Full Access and the app's switch can both change while the keyboard is hidden.
    func refresh(hasFullAccess: Bool) {
        haptics = hasFullAccess && KeyHaptics.isOn ? UIImpactFeedbackGenerator(style: .light) : nil
        haptics?.prepare()
    }

    func keyDown() {
        UIDevice.current.playInputClick()
        haptics?.impactOccurred()
        // Keeps the Taptic Engine awake for the next key, so it does not lag behind the finger.
        haptics?.prepare()
    }
}

/// `playInputClick()` is silent unless the visible input view opts in.
final class ClickingInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

extension View {
    /// Key feedback when the finger lands, once per touch. A button acts only when the finger lifts.
    func feedbackOnKeyDown() -> some View { modifier(KeyDownFeedback()) }
}

private struct KeyDownFeedback: ViewModifier {
    @GestureState private var down = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0).updating($down) { _, down, _ in
                guard !down else { return }
                down = true
                KeyFeedback.shared.keyDown()
            }
        )
    }
}
