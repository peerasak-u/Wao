import SwiftUI
import WaoCore

enum Key {
    static let capHeight: CGFloat = 42
    static let letterFill = Color(.systemGray4)
    static let specialFill = Color(.systemGray3)
}

extension View {
    /// The gap around a cap belongs to the key, so a tap between two keys still lands on one of them.
    func keyCap(_ fill: Color) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color(.label))
            .background(fill, in: RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .padding(.horizontal, KeyLayout.gap.width / 2)
            .padding(.vertical, KeyLayout.gap.height / 2)
            .contentShape(Rectangle())
    }
}

struct KeyCap: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.loopless(17))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .keyCap(Key.letterFill)
        }
        .buttonStyle(.plain)
    }
}

struct SpecialKey: View {
    private let systemImage: String?
    private let title: String?
    private let action: () -> Void

    init(systemImage: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = nil
        self.action = action
    }

    init(title: String, action: @escaping () -> Void) {
        self.systemImage = nil
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title ?? "").font(.loopless(15)).minimumScaleFactor(0.6).lineLimit(1)
                }
            }
            .keyCap(Key.specialFill)
        }
        .buttonStyle(.plain)
    }
}

/// Deletes on touch down, then repeats while held, like the system keyboard.
struct DeleteKey: View {
    let action: () -> Void
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: timer == nil ? "delete.left" : "delete.left.fill")
            .keyCap(Key.specialFill)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard timer == nil else { return }
                        action()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in action() }
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
        view.backgroundColor = .systemGray3
        view.layer.cornerRadius = 5
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension GlobeKey {
    func padded() -> some View {
        padding(.horizontal, KeyLayout.gap.width / 2).padding(.vertical, KeyLayout.gap.height / 2)
    }
}
