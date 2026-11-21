import SwiftUI
import WaoCore

/// Thai Kedmanee, QWERTY and symbols. Without Full Access this is the whole keyboard; with it, a detour from the mic.
struct TypingView: View {
    static let stripHeight: CGFloat = 28

    @ObservedObject var model: KeyboardModel
    let globe: () -> UIView?
    @State private var pressed: PlacedKey?
    @State private var explaining = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.hasFullAccess {
                    Color.clear
                } else {
                    FullAccessBanner { explaining = true }
                }
            }
            .frame(height: Self.stripHeight)
            GeometryReader { geo in
                let grid = KeyLayout(size: geo.size, rows: model.typing.rows)
                ZStack(alignment: .topLeading) {
                    ForEach(grid.keys) { key in
                        keyView(key)
                            .frame(width: key.hit.width, height: key.hit.height)
                            .position(x: key.hit.midX, y: key.hit.midY)
                    }
                    bottomRow
                        .frame(width: geo.size.width, height: grid.rowHeight)
                        .position(x: geo.size.width / 2, y: geo.size.height - grid.rowHeight / 2)
                    if let pressed, case .character(let character) = pressed.kind {
                        KeyPopup(label: model.typing.caption(of: character), font: capFont(popup: true))
                            .frame(width: max(pressed.cap.width * 1.5, 44), height: 50)
                            .position(popupCenter(for: pressed.cap, width: geo.size.width))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay {
            if explaining {
                FullAccessHelp { explaining = false }
            }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 0) {
            SpecialKey(title: model.typing.pageLabel) { model.typing.togglePage() }
                .frame(width: 50)
            if model.showsGlobe {
                GlobeKey(make: globe).padded().frame(width: 46)
            }
            SpecialKey(title: model.typing.languageLabel) { model.typing.toggleLanguage() }
                .frame(width: 50)
            if model.hasFullAccess {
                SpecialKey(systemImage: "mic.fill", action: model.showVoice)
                    .frame(width: 46)
                    .accessibilityLabel("Dictation")
            }
            KeyCap(label: model.typing.spaceLabel) { model.insert(" ") }
            SpecialKey(systemImage: "return") { model.insert("\n") }
                .frame(width: 76)
        }
    }

    @ViewBuilder
    private func keyView(_ key: PlacedKey) -> some View {
        let cap = key.cap.offsetBy(dx: -key.hit.minX, dy: -key.hit.minY)
        switch key.kind {
        case .character(let character):
            let label = model.typing.text(of: character)
            Color.clear
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    model.typing.caption(of: character)
                        .font(capFont(popup: false))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color(.label))
                        .frame(width: cap.width, height: cap.height)
                        .background(pressed?.id == key.id ? Key.specialFill : Key.letterFill, in: RoundedRectangle(cornerRadius: 5))
                        .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
                        .offset(x: cap.minX, y: cap.minY)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if pressed?.id != key.id { pressed = key } }
                        .onEnded { value in
                            if pressed?.id == key.id { pressed = nil }
                            // A finger that slid well off the key changed its mind.
                            let slack = CGRect(origin: .zero, size: key.hit.size).insetBy(dx: -16, dy: -16)
                            if slack.contains(value.location) { model.type(character) }
                        }
                )
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isKeyboardKey)
                .accessibilityAction { model.type(character) }
        case .shift:
            Group {
                if let label = model.typing.shiftLabel {
                    SpecialKey(title: label) { model.typing.toggleShift() }
                } else {
                    SpecialKey(systemImage: model.typing.shifted ? "shift.fill" : "shift") { model.typing.toggleShift() }
                        .accessibilityLabel("Shift")
                }
            }
        case .delete:
            DeleteKey(action: model.deleteBackward)
        }
    }

    private func capFont(popup: Bool) -> Font {
        let thai = model.typing.language == .thai && model.typing.page == .letters
        let size: CGFloat = popup ? 30 : 21
        return thai ? .loopless(size) : .system(size: size)
    }

    /// Sits above the key; on the top row it is pushed down into the banner strip rather than cut off.
    private func popupCenter(for cap: CGRect, width: CGFloat) -> CGPoint {
        let halfWidth = max(cap.width * 1.5, 44) / 2
        let x = min(max(cap.midX, halfWidth), width - halfWidth)
        let top = max(cap.minY - 46, -Self.stripHeight)
        return CGPoint(x: x, y: top + 25)
    }
}

extension Typing {
    func text(of key: CharacterKey) -> String { key.text(shifted: shifted) }

    /// A vowel or tone mark alone has nothing to sit on and draws as an empty key. Neither Sukhumvit Set nor the
    /// system font seats it on a dotted circle, so it sits on a faint อ instead.
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
            .background(Key.letterFill, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
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
