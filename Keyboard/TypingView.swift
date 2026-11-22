import CoreText
import SwiftUI
import WaoCore

/// Thai Kedmanee, QWERTY and symbols: the page the keyboard opens on. With Full Access its mic key leads to voice.
struct TypingView: View {
    @ObservedObject var model: KeyboardModel
    let globe: () -> UIView?
    @State private var pressed: PlacedKey?
    @State private var explaining = false

    var body: some View {
        GeometryReader { geo in
            let screen = model.screenWidth ?? geo.size.width
            let strip = KeyLayout.stripHeight(width: screen)
            let grid = KeyLayout(width: geo.size.width, screenWidth: screen, rows: model.typing.rows)
            VStack(spacing: 0) {
                let completions = model.completions
                Group {
                    if !completions.isEmpty {
                        SuggestionBar(completions: completions, choose: { model.insert($0.remainder) },
                                      explain: model.hasFullAccess ? nil : { explaining = true })
                    } else if model.hasFullAccess {
                        Color.clear
                    } else {
                        FullAccessBanner { explaining = true }
                    }
                }
                .frame(height: strip)
                ZStack(alignment: .topLeading) {
                    TouchSurfaceView { event in
                        switch event {
                        case .press(let point, let interval):
                            pressed = model.resolve(point, in: grid, interval: interval)
                        case .release(let point, let interval):
                            pressed = nil
                            if case .character(let character) = model.resolve(point, in: grid, interval: interval)?.kind {
                                model.type(character)
                            }
                        case .cancel:
                            pressed = nil
                        }
                    }
                    .frame(width: grid.characterArea.width, height: grid.characterArea.height)
                    .position(x: grid.characterArea.midX, y: grid.characterArea.midY)
                    ForEach(grid.keys) { key in
                        keyView(key, in: grid).placed(key.slot)
                    }
                    bottomRow(grid)
                    if let pressed, case .character(let character) = pressed.kind {
                        KeyPopup(label: model.typing.caption(of: character), font: popupFont)
                            .frame(width: max(pressed.cap.width * 1.5, 44), height: 50)
                            .position(popupCenter(for: pressed.cap, width: geo.size.width, strip: strip))
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
            }
        }
        .cursorTracking(model)
        .overlay {
            if explaining {
                FullAccessHelp { explaining = false }
            }
        }
    }

    /// The system keyboard's 123 and emoji, with the language key in the emoji's place; the globe (on home-button
    /// iPhones) and the mic (with Full Access) come out of the space bar.
    @ViewBuilder
    private func bottomRow(_ grid: KeyLayout) -> some View {
        let row = grid.bottomRow(leading: 2 + (model.showsGlobe ? 1 : 0) + (model.hasFullAccess ? 1 : 0))
        let typing = model.typing
        SpecialKey(title: typing.pageLabel, style: KeyFont.label(typing.pageLabel), insets: row.leading[0].insets) { model.typing.togglePage() }
            .placed(row.leading[0])
        SpecialKey(title: typing.languageLabel, style: KeyFont.label(typing.languageLabel), insets: row.leading[1].insets) { model.typing.toggleLanguage() }
            .placed(row.leading[1])
        if model.showsGlobe {
            GlobeKey(make: globe).padded(row.leading[2].insets).placed(row.leading[2])
        }
        if model.hasFullAccess, let slot = row.leading.last {
            SpecialKey(systemImage: "mic", font: KeyFont.icon(narrow: false), insets: slot.insets, action: model.showVoice)
                .accessibilityLabel("Dictation")
                .placed(slot)
        }
        SpaceKey(model: model, insets: row.space.insets)
            .placed(row.space)
        SpecialKey(systemImage: "return.left", font: KeyFont.icon(narrow: false), insets: row.enter.insets) { model.insert("\n") }
            .accessibilityLabel("Return")
            .placed(row.enter)
    }

    @ViewBuilder
    private func keyView(_ key: PlacedKey, in grid: KeyLayout) -> some View {
        let cap = key.cap.offsetBy(dx: -key.hit.minX, dy: -key.hit.minY)
        let narrow = grid.keys.count > 30
        switch key.kind {
        case .character(let character):
            let label = model.typing.text(of: character)
            // Drawn only: the touch surface beneath decides what a touch types.
            Color.clear
                .overlay(alignment: .topLeading) {
                    let style = KeyFont.letter(label)
                    Group {
                        if let mark = LoneMark(label) {
                            mark.fill(Color(.label))
                        } else {
                            Text(label)
                                .font(style.font)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(Color(.label))
                                .offset(y: style.lift)
                        }
                    }
                    .keyLabel()
                    .frame(width: cap.width, height: cap.height)
                    .background(pressed?.id == key.id ? Key.pressedFill : Key.fill, in: RoundedRectangle(cornerRadius: Key.cornerRadius))
                    .offset(x: cap.minX, y: cap.minY)
                }
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isKeyboardKey)
                .accessibilityAction { model.type(character) }
        case .shift:
            Group {
                if let label = model.typing.shiftLabel {
                    SpecialKey(title: label, style: KeyFont.label(label), insets: key.slot.insets) { model.typing.toggleShift() }
                } else {
                    SpecialKey(systemImage: model.typing.shifted ? "shift.fill" : "shift", font: KeyFont.icon(narrow: narrow), insets: key.slot.insets) {
                        model.typing.toggleShift()
                    }
                    .accessibilityLabel("Shift")
                }
            }
        case .delete:
            DeleteKey(font: KeyFont.icon(narrow: narrow), insets: key.slot.insets, action: model.deleteBackward)
        }
    }

    private var popupFont: Font {
        model.typing.language == .thai && model.typing.page == .letters ? .loopless(30) : .system(size: 30)
    }

    /// Sits above the key; on the top row it is pushed down into the suggestion strip rather than cut off.
    private func popupCenter(for cap: CGRect, width: CGFloat, strip: CGFloat) -> CGPoint {
        let halfWidth = max(cap.width * 1.5, 44) / 2
        let x = min(max(cap.midX, halfWidth), width - halfWidth)
        let top = max(cap.minY - 46, -strip)
        return CGPoint(x: x, y: top + 25)
    }
}

/// The system keyboard's label faces and sizes, matched to its screenshots by the label boxes that
/// tools/keyboard_parity.py prints.
enum KeyFont {
    /// A character cap: Thai in Thonburi Light, lower-case Latin larger than capitals and figures, as iOS draws them.
    /// `lift` moves the label from the cap's centre to where the system keyboard's sits.
    static func letter(_ text: String) -> (font: Font, lift: CGFloat) {
        if text.isThai { return (.custom("Thonburi-Light", size: 24), -4.5) }
        let lowercase = text.lowercased() == text && text.uppercased() != text
        if lowercase { return (.system(size: 25), -2.3) }
        return (figures, -1.2 + (sunk[text] ?? 0))
    }

    /// How much lower than the figures' baseline iOS sets these, measured on its numbers page.
    private static let sunk: [String: CGFloat] = [".": 3, ",": 3, ":": 2.8]

    /// Capitals, figures and symbols, with the case-sensitive forms that raise dashes and brackets to the figures.
    private static let figures: Font = {
        let feature: [UIFontDescriptor.FeatureKey: Int] = [.type: kCaseSensitiveLayoutType, .selector: kCaseSensitiveLayoutOnSelector]
        let font = UIFont.systemFont(ofSize: 22)
        return Font(UIFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: [feature]]), size: 22))
    }()

    /// 123, ABC, กขค, #+= and the like.
    static func label(_ text: String) -> (font: Font, lift: CGFloat) {
        if text.isThai { return (.custom("Thonburi", size: 16), -1.5) }
        return (text.count > 2 && text.allSatisfy({ !$0.isLetter && !$0.isNumber }) ? .system(size: 13) : .system(size: 18.5), 0)
    }

    /// Shift, delete, return and the mic; smaller on the twelve-column Thai rows.
    static func icon(narrow: Bool) -> Font { .system(size: narrow ? 15 : 19, weight: .regular) }
}

/// A vowel or tone mark drawn alone, as the system keyboard draws it. As text, Thonburi seats a lone mark on a dotted
/// circle, and on a consonant it fuses the two into one glyph; so the pair อ + mark is shaped and the outline's
/// pieces that overlap a lone อ are dropped. ำ counts as a mark: it carries a nikhahit.
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

extension View {
    func placed(_ slot: KeySlot) -> some View {
        frame(width: slot.hit.width, height: slot.hit.height).position(x: slot.hit.midX, y: slot.hit.midY)
    }
}

private extension String {
    var isThai: Bool { unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) } }
}

extension Typing {
    func text(of key: CharacterKey) -> String { key.text(shifted: shifted) }

    /// The popup's label. A vowel or tone mark alone has nothing to sit on and draws as an empty key. Neither
    /// Sukhumvit Set nor the system font seats it on a dotted circle, so it sits on a faint อ instead.
    func caption(of key: CharacterKey) -> Text {
        let text = text(of: key)
        guard text.unicodeScalars.first?.properties.generalCategory == .nonspacingMark else { return Text(text) }
        return Text("อ").foregroundColor(Color(.label).opacity(0.6)) + Text(text)
    }
}

private struct KeyPopup: View {
    let label: Text
    let font: Font

    var body: some View {
        label
            .font(font)
            .foregroundStyle(Color(.label))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray4), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

/// Up to three words that finish the one being typed: the likeliest in the middle, as on the system keyboard.
private struct SuggestionBar: View {
    let completions: [Completion]
    let choose: (Completion) -> Void
    /// Without Full Access the bar takes the banner's place, so its way to the help stays at the trailing edge.
    let explain: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array([1, 0, 2].enumerated()), id: \.offset) { position, rank in
                if position > 0 { Divider().frame(height: 22) }
                Group {
                    if rank < completions.count {
                        Button { choose(completions[rank]) } label: {
                            Text(label(completions[rank]))
                                .font(.loopless(17))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if let explain {
                Button(action: explain) {
                    Image(systemName: "mic.slash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Full Access")
            }
        }
        .padding(.horizontal, 4)
    }

    /// What has been typed already reads fainter than what a tap adds.
    private func label(_ completion: Completion) -> AttributedString {
        var text = AttributedString(completion.word)
        text.foregroundColor = Color(.label)
        let added = completion.remainder.unicodeScalars.count
        let typed = text.unicodeScalars.index(text.unicodeScalars.endIndex, offsetBy: -added)
        text[text.startIndex..<typed].foregroundColor = Color(.secondaryLabel)
        return text
    }
}

private struct FullAccessBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "mic.slash")
                Text("เปิดการเข้าถึงแบบเต็มเพื่อพิมพ์ด้วยเสียง")
                    .font(.loopless(13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "info.circle")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(.secondaryLabel))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// There is no reliable way to open Settings from a keyboard, so the path is spelled out.
private struct FullAccessHelp: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("พิมพ์ด้วยเสียงต้องเปิดการเข้าถึงแบบเต็ม")
                .font(.loopless(17, .semibold))
            Text("การตั้งค่า › ทั่วไป › แป้นพิมพ์ › แป้นพิมพ์ › เว่า › เปิด \"อนุญาตการเข้าถึงแบบเต็ม\"")
                .font(.loopless(15))
                .fixedSize(horizontal: false, vertical: true)
            Text("แป้นพิมพ์ใช้สิทธิ์นี้เพื่อส่งเสียงไปถอดความในแอปเว่าบนเครื่องนี้ ระหว่างนี้พิมพ์ด้วยแป้นได้ตามปกติ")
                .font(.loopless(13))
                .foregroundStyle(Color(.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("แตะเพื่อกลับไปพิมพ์")
                .font(.loopless(13, .medium))
                .foregroundStyle(Color(.secondaryLabel))
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color(.label))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
        .padding(4)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
    }
}
