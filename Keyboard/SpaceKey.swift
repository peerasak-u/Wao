import SwiftUI
import UIKit
import WaoCore

/// Space types a space on a tap. Held, the keyboard becomes a trackpad for the cursor, as on the system keyboard.
struct SpaceKey: View {
    @ObservedObject var model: KeyboardModel
    let insets: EdgeInsets
    @State private var down = false

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                // The faint letter in the corner of the blank space bar, as on the iOS 26.4 Thai keyboard.
                Text("ก")
                    .font(.custom("Thonburi", size: 12))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(.trailing, 6)
                    .padding(.bottom, 3)
                    .keyLabel()
            }
            .keyCap(down && !model.tracksCursor ? Key.pressedFill : Key.fill, insets: insets)
            .overlay {
                SpaceTouchView(tracking: model.tracksCursor, down: { down = $0 }) { effect in
                    switch effect {
                    case .space: model.insert(" ")
                    case .begin:
                        KeyFeedback.shared.trackpadBegan()
                        model.beginCursorTracking()
                    case .move(let columns, let lines): model.moveCursor(columns: columns, lines: lines)
                    case .end: model.endCursorTracking()
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("space")
            .accessibilityAddTraits(.isKeyboardKey)
            .accessibilityAction { model.insert(" ") }
    }
}

/// UIKit keeps a touch with the view it landed on, so a held space can roam the whole keyboard and beyond.
final class SpaceTouch: UIView {
    var onEffect: (SpaceTrackpad.Effect) -> Void = { _ in }
    var onDown: (Bool) -> Void = { _ in }
    private var pad = SpaceTrackpad()
    private var finger: UITouch?
    private var hold: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Something else ended trackpad mode, a finger on another key.
    func interrupt() {
        send(pad.interrupted())
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            if finger == nil, pad.phase == .idle {
                finger = touch
                onDown(true)
                KeyFeedback.shared.keyDown()
                send(pad.down(at: touch.location(in: self)))
                let hold = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.send(self.pad.held())
                }
                self.hold = hold
                DispatchQueue.main.asyncAfter(deadline: .now() + SpaceTrackpad.holdDelay, execute: hold)
            } else {
                send(pad.down(at: touch.location(in: self)))
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let finger, touches.contains(finger) else { return }
        var columns = 0, lines = 0
        for sample in event?.coalescedTouches(for: finger) ?? [finger] {
            let point = sample.location(in: self)
            let onKey = bounds.insetBy(dx: -16, dy: -16).contains(point)
            if case .move(let c, let l) = pad.moved(to: point, at: sample.timestamp, onKey: onKey) {
                columns += c
                lines += l
            }
        }
        send(columns != 0 || lines != 0 ? .move(columns: columns, lines: lines) : nil)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let finger, touches.contains(finger) else { return }
        self.finger = nil
        onDown(false)
        send(pad.lifted())
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let finger, touches.contains(finger) else { return }
        self.finger = nil
        onDown(false)
        send(pad.cancelled())
    }

    private func send(_ effect: SpaceTrackpad.Effect?) {
        if case .pressed = pad.phase {} else {
            hold?.cancel()
            hold = nil
        }
        if let effect { onEffect(effect) }
    }
}

private struct SpaceTouchView: UIViewRepresentable {
    let tracking: Bool
    let down: (Bool) -> Void
    let onEffect: (SpaceTrackpad.Effect) -> Void

    func makeUIView(context: Context) -> SpaceTouch { SpaceTouch() }

    func updateUIView(_ view: SpaceTouch, context: Context) {
        view.onEffect = onEffect
        view.onDown = down
        if !tracking { view.interrupt() }
    }
}

extension EnvironmentValues {
    /// In trackpad mode the keys go blank, as on the system keyboard.
    @Entry var keyLabelsHidden = false
}

extension View {
    func keyLabel() -> some View { modifier(KeyLabel()) }

    /// While the cursor tracks, a finger anywhere else on the keyboard ends trackpad mode instead of typing.
    func cursorTracking(_ model: KeyboardModel) -> some View {
        environment(\.keyLabelsHidden, model.tracksCursor)
            .overlay {
                if model.tracksCursor {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in model.endCursorTracking() })
                }
            }
    }
}

private struct KeyLabel: ViewModifier {
    @Environment(\.keyLabelsHidden) private var hidden

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: hidden)
    }
}
