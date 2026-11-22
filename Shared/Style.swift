import SwiftUI
import WaoCore

/// Bars mirrored around the centre: the newest level sits in the middle and older ones move outwards, so each
/// sound spreads from the centre. Bars shrink and fade towards the edges, down to dots, under a glow that
/// follows the voice.
struct Waveform: View {
    static let barsPerSide = 11

    let levels: [Float]
    let active: Bool
    /// The app's hero while it records: a stronger glow and outline, so the pill reads as live.
    var lit = false

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
            RadialGradient(colors: [ink.opacity((lit ? 0.7 : 0.45) * newest), .clear], center: .center, startRadius: 0, endRadius: lit ? 90 : 60)
                .blur(radius: 10)
        }
        .background(ink.opacity(lit ? 0.07 : 0.03))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(ink.opacity(lit ? 0.4 : 0.12), lineWidth: lit ? 1.5 : 1))
        .shadow(color: ink.opacity(lit ? 0.18 + 0.3 * newest : 0), radius: 20)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    /// The level `age` steps before the newest one.
    private func level(_ age: Int) -> CGFloat {
        guard active, age < levels.count else { return 0 }
        return CGFloat(levels[levels.count - 1 - age])
    }
}

/// The preview from the top of its box; once it runs past three lines its start is clipped off the top, so the
/// words being spoken stay in view.
struct HeardText: View {
    static let size: CGFloat = 21
    static let lineHeight = lineHeight(fontName: nil)

    static func lineHeight(fontName: String?) -> CGFloat {
        (fontName.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size, weight: .medium)).lineHeight
    }

    let heard: Heard
    let settled: Bool
    var fontName: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text((heard.clipped ? "…" : "") + heard.text)
                .font(fontName.map { .custom($0, fixedSize: Self.size) } ?? .system(size: Self.size, weight: .medium))
                .foregroundStyle(Color(.label).opacity(settled ? 0.4 : 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: Self.lineHeight(fontName: fontName) * 3, alignment: .bottom)
                // Without this the cap takes the whole offered height and short text sinks to the bottom.
                .fixedSize(horizontal: false, vertical: true)
                .clipped()
                .frame(maxHeight: .infinity, alignment: .top)
            if settled { ProgressView() }
        }
    }
}
