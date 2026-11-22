import SwiftUI
import UIKit

enum Palette {
    enum UI {
        static let canvas = adaptive(light: 0xFBFAF6, dark: 0x151514)
        static let ink = adaptive(light: 0x161614, dark: 0xF3F1EA)
        static let hairline = ink(0.15)

        static func canvas(_ alpha: CGFloat) -> UIColor { adaptive(light: 0xFBFAF6, dark: 0x151514, alpha: alpha) }
        static func ink(_ alpha: CGFloat) -> UIColor { adaptive(light: 0x161614, dark: 0xF3F1EA, alpha: alpha) }

        private static func adaptive(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> UIColor {
            UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: alpha
                )
            }
        }
    }

    static let canvas = Color(uiColor: UI.canvas)
    static let ink = Color(uiColor: UI.ink)
    static let secondary = Color(uiColor: UI.ink(0.62))
    static let tertiary = Color(uiColor: UI.ink(0.40))
    static let hairline = Color(uiColor: UI.hairline)
    static let dot = Color(uiColor: UI.ink(0.20))
}

enum InkFont {
    static let regular = "Anuphan-Regular"
    static let medium = "Anuphan-Medium"
    static let semibold = "Anuphan-SemiBold"
    static let bold = "Anuphan-Bold"
    static let hand = "Itim-Regular"

    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .medium: medium
        case .semibold: semibold
        case .bold, .heavy, .black: bold
        default: regular
        }
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular, fallback: UIFont.Weight = .regular) -> UIFont {
        UIFont(name: name(for: weight), size: size) ?? .systemFont(ofSize: size, weight: fallback)
    }
}

extension Font {
    static func ink(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(InkFont.name(for: weight), fixedSize: size)
    }

    static func hand(_ size: CGFloat) -> Font {
        .custom(InkFont.hand, fixedSize: size)
    }
}

extension View {
    func screenBackground() -> some View {
        font(.ink(16))
            .foregroundStyle(Palette.ink)
            .background {
                ZStack {
                    Palette.canvas
                    DotGrid()
                        .mask(LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .clear, location: 0.55),
                        ], startPoint: .top, endPoint: .bottom))
                }
                .ignoresSafeArea()
            }
    }

    func card(lit: Bool = false) -> some View {
        background(Palette.canvas, in: InkShape.card)
            .overlay(InkShape.card.strokeBorder(Palette.ink, lineWidth: lit ? 2 : 1.5))
    }

    func pill(prominent: Bool) -> some View {
        foregroundStyle(prominent ? Palette.canvas : Palette.ink)
            .background {
                if prominent {
                    Capsule().fill(Palette.ink)
                } else {
                    Capsule().fill(Palette.canvas)
                        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1.5))
                }
            }
    }
}

enum InkShape {
    /// Slightly unequal corners, so a box reads as drawn by hand.
    static let card = UnevenRoundedRectangle(
        topLeadingRadius: 20, bottomLeadingRadius: 16, bottomTrailingRadius: 21, topTrailingRadius: 17,
        style: .continuous
    )
}

private struct DotGrid: View {
    private static let diameter: CGFloat = 1.8
    private static let spacing: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for y in stride(from: Self.spacing / 2, to: size.height, by: Self.spacing) {
                for x in stride(from: Self.spacing / 2, to: size.width, by: Self.spacing) {
                    dots.addEllipse(in: CGRect(x: x - Self.diameter / 2, y: y - Self.diameter / 2, width: Self.diameter, height: Self.diameter))
                }
            }
            context.fill(dots, with: .color(Palette.dot))
        }
    }
}

struct PillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ink(14, prominent ? .semibold : .medium))
                .padding(.horizontal, prominent ? 18 : 14)
                .frame(minHeight: 32)
                .pill(prominent: prominent)
        }
        .buttonStyle(Pressable())
    }
}

struct Pressable: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct InkSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Palette.ink : Palette.canvas)
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1.5))
                .frame(width: 46, height: 27)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Palette.canvas : Palette.ink)
                        .padding(5)
                }
                .animation(.snappy(duration: 0.2), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

struct StrokeProgress: View {
    private static let count = 16

    let value: Double

    var body: some View {
        let filled = Int(value * Double(Self.count))
        HStack(spacing: 6) {
            ForEach(0..<Self.count, id: \.self) { i in
                Image(decorative: "MaiEk")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 20)
                    .foregroundStyle(i < filled ? Palette.ink : Palette.hairline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut, value: filled)
    }
}

/// The typeset word without its tone mark, with the hand-drawn ไม้เอก laid over where the mark belongs.
struct Wordmark: View {
    private enum Tone {
        static let topPadding: CGFloat = 0.2
        static let x: CGFloat = 0.79
        static let y: CGFloat = 0.02
        static let height: CGFloat = 0.5
    }

    let size: CGFloat

    var body: some View {
        Text(verbatim: "เวา")
            .font(.ink(size, .bold))
            .padding(.top, size * Tone.topPadding)
            .overlay(alignment: .topLeading) {
                Image(decorative: "MaiEk")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: size * Tone.height)
                    .offset(x: size * Tone.x, y: size * Tone.y)
            }
            .accessibilityRepresentation { Text("เว่า") }
    }
}

/// A note written beside something, with a curved arrow pointing back at it.
struct HandNote<Content: View>: View {
    enum Pointing {
        case left, upLeft

        var angle: Angle { self == .left ? .zero : .degrees(35) }
    }

    var pointing: Pointing?
    var size: CGFloat = 17
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if let pointing {
                Image(decorative: "InkArrow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44)
                    .scaleEffect(x: -1)
                    .rotationEffect(pointing.angle)
            }
            content
                .font(.hand(size))
                .foregroundStyle(Palette.ink)
        }
    }
}
