import SwiftUI
import WaoCore

enum Key {
    /// The default room around a cap; the typing pages place their caps with `KeyLayout` and pass their own.
    static let gap = CGSize(width: 5, height: 8)
    static let gapInsets = EdgeInsets(top: gap.height / 2, leading: gap.width / 2, bottom: gap.height / 2, trailing: gap.width / 2)
    /// The system keyboard draws every key, letters and specials alike, in one flat colour without a shadow.
    static let fillColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 60 / 255, alpha: 1) : .white }
    static let fill = Color(fillColor)
    static let pressedFill = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : UIColor(white: 0.82, alpha: 1) })
    static let cornerRadius: CGFloat = 8
}

extension KeySlot {
    /// Where the cap sits inside the hit area.
    var insets: EdgeInsets {
        EdgeInsets(top: cap.minY - hit.minY, leading: cap.minX - hit.minX, bottom: hit.maxY - cap.maxY, trailing: hit.maxX - cap.maxX)
    }
}

extension View {
    /// The gap around a cap belongs to the key, so a tap between two keys still lands on one of them.
    func keyCap(_ fill: Color, insets: EdgeInsets = Key.gapInsets) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color(.label))
            .background(fill, in: RoundedRectangle(cornerRadius: Key.cornerRadius))
            .padding(insets)
            .contentShape(Rectangle())
    }
}

/// Draws the button as a cap that darkens while held.
struct KeyPress: ButtonStyle {
    var insets = Key.gapInsets

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.keyCap(configuration.isPressed ? Key.pressedFill : Key.fill, insets: insets)
    }
}

struct SpecialKey: View {
    private let systemImage: String?
    private let title: String?
    private let font: Font
    private let lift: CGFloat
    private let insets: EdgeInsets
    private let action: () -> Void

    init(systemImage: String, font: Font = .body, insets: EdgeInsets = Key.gapInsets, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = nil
        self.font = font
        self.lift = 0
        self.insets = insets
        self.action = action
    }

    /// `style.lift` moves the title up or down from the cap's centre.
    init(title: String, style: (font: Font, lift: CGFloat), insets: EdgeInsets = Key.gapInsets, action: @escaping () -> Void) {
        self.systemImage = nil
        self.title = title
        self.font = style.font
        self.lift = style.lift
        self.insets = insets
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title ?? "").minimumScaleFactor(0.6).lineLimit(1).offset(y: lift)
                }
            }
            .font(font)
            .keyLabel()
        }
        .buttonStyle(KeyPress(insets: insets))
        .feedbackOnKeyDown()
    }
}

/// Deletes on touch down, then repeats while held, like the system keyboard.
struct DeleteKey: View {
    var font: Font = .body
    var insets = Key.gapInsets
    /// No cap, as on the emoji keyboard's bar; the cap shows only while held.
    var bare = false
    let action: () -> Void
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: "delete.left")
            .font(font)
            .keyLabel()
            .keyCap(timer != nil ? Key.pressedFill : bare ? .clear : Key.fill, insets: insets)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard timer == nil else { return }
                        press()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in press() }
                        }
                    }
                    .onEnded { _ in stop() }
            )
            .onDisappear(perform: stop)
            .accessibilityElement()
            .accessibilityLabel("Delete")
            .accessibilityAddTraits(.isKeyboardKey)
            .accessibilityAction { action() }
    }

    /// Each repeat clicks, as the system keyboard's delete does.
    private func press() {
        KeyFeedback.shared.keyDown()
        action()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// The globe has to be a UIKit control so `handleInputModeList(from:with:)` gets real touch events.
struct GlobeKey: UIViewRepresentable {
    let make: () -> UIView?

    func makeUIView(context: Context) -> UIView {
        let view = make() ?? UIView()
        view.backgroundColor = Key.fillColor
        view.layer.cornerRadius = Key.cornerRadius
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension GlobeKey {
    func padded(_ insets: EdgeInsets = Key.gapInsets) -> some View {
        padding(insets)
    }
}
