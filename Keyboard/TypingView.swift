import SwiftUI
import WaoTyping

/// Thai Kedmanee and symbols: the page the keyboard opens on. With Full Access its mic key starts dictation.
struct TypingView: View {
    @ObservedObject var model: KeyboardModel
    let globe: () -> UIView?
    @State private var explaining = false

    var body: some View {
        GeometryReader { geo in
            let screen = model.screenWidth ?? geo.size.width
            let strip = KeyLayout.stripHeight(width: screen)
            let grid = KeyLayout(width: geo.size.width, screenWidth: screen, rows: model.typing.rows)
            VStack(spacing: 0) {
                let completions = model.completions
                HStack(spacing: 0) {
                    if model.pending != nil {
                        TranscribingMark(captioned: completions.isEmpty)
                    }
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
                KeyArea(model: model, globe: globe, grid: grid, popupRoom: strip)
            }
        }
        .cursorTracking(model)
        .overlay {
            if explaining {
                FullAccessHelp { explaining = false }
            }
        }
    }
}

/// The Thai and symbol keys with the bottom row, for the typing page and emoji search. In search the keys type into
/// the query (the model routes them), space has no trackpad, return and the emoji key go back to the grid, and the
/// mic is gone.
struct KeyArea: View {
    @ObservedObject var model: KeyboardModel
    let globe: () -> UIView?
    let grid: KeyLayout
    /// How far above the keys the top row's popup may reach.
    let popupRoom: CGFloat
    @State private var pressed: PlacedKey?

    var body: some View {
        ZStack(alignment: .topLeading) {
            TouchSurfaceView { event in
                switch event {
                case .press(let point, let interval):
                    // A press comes on every finger move; the keys redraw only when it lands on another key.
                    let key = model.resolve(point, in: grid, interval: interval)
                    if key != pressed { pressed = key }
                case .release(let point, let interval):
                    pressed = nil
                    if case .character(let character) = model.resolve(point, in: grid, interval: interval)?.kind {
                        model.tap(character, at: point, interval: interval, in: grid)
                    }
                case .cancel:
                    pressed = nil
                }
            }
            .frame(width: grid.characterArea.width, height: grid.characterArea.height)
            .position(x: grid.characterArea.midX, y: grid.characterArea.midY)
            ForEach(grid.keys) { key in
                keyView(key).placed(key.slot)
            }
            bottomRow
            if let pressed, case .character(let character) = pressed.kind {
                KeyPopup(text: model.typing.text(of: character))
                    .frame(width: max(pressed.cap.width * 1.5, 44), height: 50)
                    .position(popupCenter(for: pressed.cap))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
    }

    /// The system keyboard's 123 and emoji; the globe (on home-button iPhones) and the mic (with Full Access) come out
    /// of the space bar.
    @ViewBuilder
    private var bottomRow: some View {
        let mic = model.hasFullAccess && !model.isSearchingEmoji
        let row = grid.bottomRow(leading: 2 + (model.showsGlobe ? 1 : 0) + (mic ? 1 : 0))
        let typing = model.typing
        SpecialKey(title: typing.pageLabel, style: KeyFont.label(typing.pageLabel), insets: row.leading[0].insets) { model.typing.togglePage() }
            .placed(row.leading[0])
        SpecialKey(systemImage: "face.smiling", font: KeyFont.icon(narrow: false), insets: row.leading[1].insets, action: model.showEmoji)
            .accessibilityLabel("Emoji")
            .placed(row.leading[1])
        if model.showsGlobe {
            GlobeKey(make: globe).padded(row.leading[2].insets).placed(row.leading[2])
        }
        if mic, let slot = row.leading.last {
            SpecialKey(systemImage: "mic", font: KeyFont.icon(narrow: false), insets: slot.insets, action: model.micTapped)
                .accessibilityLabel("Dictation")
                .placed(slot)
        }
        SpaceKey(model: model, insets: row.space.insets, trackpad: !model.isSearchingEmoji)
            .placed(row.space)
        SpecialKey(systemImage: "return.left", font: KeyFont.icon(narrow: false), insets: row.enter.insets, action: model.returnKey)
            .accessibilityLabel("Return")
            .placed(row.enter)
    }

    @ViewBuilder
    private func keyView(_ key: PlacedKey) -> some View {
        let cap = key.cap.offsetBy(dx: -key.hit.minX, dy: -key.hit.minY)
        let narrow = grid.keys.count > 30
        switch key.kind {
        case .character(let character):
            let label = model.typing.text(of: character)
            // Drawn only: the touch surface beneath decides what a touch types.
            Color.clear
                .overlay(alignment: .topLeading) {
                    CapLabel(text: label)
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
            DeleteKey(font: KeyFont.icon(narrow: narrow), insets: key.slot.insets, action: model.delete)
        }
    }

    /// Sits above the key; on the top row it is pushed down into the room above the keys rather than cut off.
    private func popupCenter(for cap: CGRect) -> CGPoint {
        let halfWidth = max(cap.width * 1.5, 44) / 2
        let x = min(max(cap.midX, halfWidth), grid.size.width - halfWidth)
        let top = max(cap.minY - 46, -popupRoom)
        return CGPoint(x: x, y: top + 25)
    }
}

extension View {
    func placed(_ slot: KeySlot) -> some View {
        frame(width: slot.hit.width, height: slot.hit.height).position(x: slot.hit.midX, y: slot.hit.midY)
    }
}

extension Typing {
    func text(of key: CharacterKey) -> String { key.text(shifted: shifted) }
}

/// Text confirmed with ✓ is still on its way. It sits beside the suggestions, and gives up its caption to them.
private struct TranscribingMark: View {
    let captioned: Bool

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            if captioned {
                Text("กำลังถอดเสียง")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, captioned ? 0 : 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("กำลังถอดเสียง")
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
                                .font(.system(size: 17))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .feedbackOnKeyDown()
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
                    .font(.system(size: 13))
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
                .font(.system(size: 17, weight: .semibold))
            Text("การตั้งค่า › ทั่วไป › แป้นพิมพ์ › แป้นพิมพ์ › เว่า › เปิด \"อนุญาตการเข้าถึงแบบเต็ม\"")
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
            Text("แป้นพิมพ์ใช้สิทธิ์นี้เพื่อส่งเสียงไปถอดความในแอปเว่าบนเครื่องนี้ ระหว่างนี้พิมพ์ด้วยแป้นได้ตามปกติ")
                .font(.system(size: 13))
                .foregroundStyle(Color(.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("แตะเพื่อกลับไปพิมพ์")
                .font(.system(size: 13, weight: .medium))
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
