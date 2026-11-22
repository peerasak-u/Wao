import CoreText
import SwiftUI

/// The system keyboard's label faces and sizes, matched to its screenshots by the label boxes and ink that
/// tools/keyboard_parity.py prints.
enum KeyFont {
    /// 123, กขค, #+= and the like.
    static func label(_ text: String) -> (font: Font, lift: CGFloat) {
        if text.isThai { return (.custom("Thonburi", size: 16), -1.5) }
        return (text.count > 2 && text.allSatisfy({ !$0.isLetter && !$0.isNumber }) ? .system(size: 13) : .system(size: 18.5), 0)
    }

    /// Shift, delete, return and the mic; smaller on the twelve-column Thai rows.
    static func icon(narrow: Bool) -> Font { .system(size: narrow ? 15 : 19, weight: .regular) }
}

/// The face iOS draws its own Thai caps and popups in. It is Thonburi redrawn for a cap: ไ ใ โ ฬ ำ are shorter, and a
/// vowel or tone mark stands alone instead of on a dotted circle. It has no public name, so it is read from its file;
/// if a later iOS moves it, the caps fall back to Thonburi.
private enum Keycaps {
    static let keys = font(".Keycaps-Keys", size: 23)
    static let popups = font(".Keycaps-Popups", size: 37.5)
    /// Centring the face's line box on the cap puts its baseline this far above where iOS has it.
    static let lift: CGFloat = 0.8

    private static func font(_ name: String, size: CGFloat) -> Font? {
        // A simulator keeps the system's files under its runtime root.
        let root = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] ?? ""
        let url = URL(fileURLWithPath: root + "/System/Library/Fonts/CoreUI/Keycaps.ttc") as CFURL
        let faces = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor] ?? []
        let face = faces.first { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == name }
        return face.map { Font(CTFontCreateWithFontDescriptor($0, size, nil)) }
    }
}

/// A character cap's label: Thai in Keycaps, figures and symbols in the system font, as iOS draws them.
struct CapLabel: View {
    let text: String

    var body: some View {
        if text.isThai, let font = Keycaps.keys {
            line(font, lift: Keycaps.lift)
        } else if let mark = LoneMark(text) {
            mark.fill(Color(.label))
        } else if text.isThai {
            line(.custom("Thonburi-Light", size: 24), lift: -4.5)
        } else {
            line(Self.figures, lift: -1.2 + (Self.sunk[text] ?? 0))
        }
    }

    private func line(_ font: Font, lift: CGFloat) -> some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Color(.label))
            .offset(y: lift)
    }

    /// How much lower than the figures' baseline iOS sets these, measured on its numbers page.
    private static let sunk: [String: CGFloat] = [".": 3, ",": 3, ":": 2.8]

    /// Figures and symbols, with the case-sensitive forms that raise dashes and brackets to the figures.
    private static let figures: Font = {
        let feature: [UIFontDescriptor.FeatureKey: Int] = [.type: kCaseSensitiveLayoutType, .selector: kCaseSensitiveLayoutOnSelector]
        let font = UIFont.systemFont(ofSize: 22)
        return Font(UIFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: [feature]]), size: 22))
    }()
}

/// The enlarged key above a pressed cap.
struct KeyPopup: View {
    let text: String

    var body: some View {
        label
            .foregroundStyle(Color(.label))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray4), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    private var label: Text {
        if !text.isThai { return Text(text).font(.system(size: 30)) }
        if let font = Keycaps.popups { return Text(text).font(font) }
        // Thonburi seats a lone mark on a dotted circle, so without Keycaps it sits on a faint อ instead.
        let mark = text.unicodeScalars.first?.properties.generalCategory == .nonspacingMark
        let base = mark ? Text("อ").foregroundColor(Color(.label).opacity(0.6)) : Text("")
        return (base + Text(text)).font(.custom("Thonburi", size: 30))
    }
}


/// Without Keycaps, a vowel or tone mark drawn alone, as the system keyboard draws it. As text, Thonburi seats a lone
/// mark on a dotted circle, and on a consonant it fuses the two into one glyph; so the pair อ + mark is shaped and the
/// outline's pieces that overlap a lone อ are dropped. ำ counts as a mark: it carries a nikhahit.
struct LoneMark: Shape {
    private let outline: Path
    /// The mark's centre as a fraction of the cap's height from its middle, measured on the system keyboard.
    private let drop: CGFloat

    init?(_ text: String) {
        guard let first = text.unicodeScalars.first else { return nil }
        let below: Set<Unicode.Scalar> = ["\u{0E38}", "\u{0E39}", "\u{0E3A}"]
        if first == "\u{0E33}" {
            (outline, drop) = (Self.mark(text, size: 22), -0.07)
        } else if first.properties.generalCategory == .nonspacingMark {
            // The system keyboard draws lone marks about a third larger than its letters.
            (outline, drop) = (Self.mark(text, size: 32), below.contains(first) ? 0.116 : -0.196)
        } else {
            return nil
        }
    }

    private static func mark(_ text: String, size: CGFloat) -> Path {
        let font = CTFontCreateWithName("Thonburi-Light" as CFString, size, nil)
        let base = glyphs("อ", font).boundingBoxOfPath.insetBy(dx: 1, dy: 1)
        let kept = glyphs("อ" + text, font).componentsSeparated().filter { !$0.boundingBoxOfPath.intersects(base) }
        var path = Path()
        // CoreText outlines are y-up from the baseline.
        for piece in kept { path.addPath(Path(piece), transform: CGAffineTransform(scaleX: 1, y: -1)) }
        return path
    }

    private static func glyphs(_ text: String, _ font: CTFont) -> CGPath {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                if let outline = CTFontCreatePathForGlyph(font, glyph, nil) {
                    path.addPath(outline, transform: CGAffineTransform(translationX: position.x, y: position.y))
                }
            }
        }
        return path
    }

    func path(in rect: CGRect) -> Path {
        let ink = outline.boundingRect
        return outline.offsetBy(dx: rect.midX - ink.midX, dy: rect.midY + drop * rect.height - ink.midY)
    }
}

private extension String {
    var isThai: Bool { unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) } }
}
