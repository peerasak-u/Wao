import SwiftUI
import UIKit

/// The character keys' touches. SwiftUI gestures cannot order two fingers that overlap or say when a touch began,
/// and both decide what a tap types.
final class TouchSurface: UIView {
    enum Event {
        /// A finger is down at this point, `interval` seconds after the previous character touch went down.
        case press(CGPoint, interval: TimeInterval)
        case release(CGPoint, interval: TimeInterval)
        case cancel
    }

    var onEvent: (Event) -> Void = { _ in }
    /// The one finger still down; an earlier one was committed when this one landed.
    private var live: (touch: UITouch, interval: TimeInterval)?
    private var lastDown: TimeInterval?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A second finger commits the first, so letters come out in the order they were touched.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let (earlier, interval) = live { onEvent(.release(clamped(earlier), interval: interval)) }
            let interval = lastDown.map { touch.timestamp - $0 } ?? .infinity
            lastDown = touch.timestamp
            live = (touch, interval)
            onEvent(.press(clamped(touch), interval: interval))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let (touch, interval) = live, touches.contains(touch) else { return }
        onEvent(.press(clamped(touch), interval: interval))
    }

    /// A finger that slid well off the keys changed its mind.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let (touch, interval) = live, touches.contains(touch) else { return }
        live = nil
        let slack = bounds.insetBy(dx: -16, dy: -16)
        onEvent(slack.contains(touch.location(in: self)) ? .release(clamped(touch), interval: interval) : .cancel)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let (touch, _) = live, touches.contains(touch) else { return }
        live = nil
        onEvent(.cancel)
    }

    private func clamped(_ touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: min(max(p.x, 0), bounds.maxX - 0.01), y: min(max(p.y, 0), bounds.maxY - 0.01))
    }
}

struct TouchSurfaceView: UIViewRepresentable {
    let onEvent: (TouchSurface.Event) -> Void

    func makeUIView(context: Context) -> TouchSurface { TouchSurface() }

    func updateUIView(_ surface: TouchSurface, context: Context) { surface.onEvent = onEvent }
}
