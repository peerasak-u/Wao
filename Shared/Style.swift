import SwiftUI

/// Bars mirrored around the centre: the newest level sits in the middle and older ones move outwards, so each
/// sound spreads from the centre. Bars shrink and fade towards the edges, down to dots, under a glow that
/// follows the voice.
struct Waveform: View {
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

extension Font {
    enum Face: String { case thin = "Thin", light = "Light", text = "Text", medium = "Medium", semibold = "SemiBold", bold = "Bold" }

    /// Sukhumvit Set ships with iOS and has no loops (หัว); the system's Thai fallback, Thonburi, does.
    static func loopless(_ size: CGFloat, _ face: Face = .text) -> Font {
        .custom("SukhumvitSet-\(face.rawValue)", size: size)
    }
}
