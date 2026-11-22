import SwiftUI
import UIKit
import WaoCore

/// Apple's emoji search: the field over a row of results, over the Thai keys that type the query. It keeps the emoji
/// page's height, so the host stays put.
struct EmojiSearchView: View {
    @ObservedObject var model: KeyboardModel
    let query: String
    let globe: () -> UIView?
    @State private var history = EmojiHistory.stored
    /// Frequently used as it was when search opened, so nothing moves under the finger while picking.
    @State private var frequent: [String] = EmojiHistory.stored.recent

    var body: some View {
        GeometryReader { geo in
            let screen = model.screenWidth ?? geo.size.width
            let inset = (screen - geo.size.width) / 2
            let grid = KeyLayout(width: geo.size.width, screenWidth: screen, rows: model.typing.rows)
            let results = geo.size.height - grid.size.height - EmojiMetrics.searchTop - EmojiMetrics.search
            VStack(spacing: 0) {
                EmojiSearchField(query: query, tap: model.showEmoji)
                    .frame(height: EmojiMetrics.search)
                    .padding(.horizontal, EmojiMetrics.searchMargin - inset)
                    .padding(.top, EmojiMetrics.searchTop)
                EmojiResults(items: items, empty: query.isEmpty ? "" : "ไม่พบอีโมจิ", pick: pick)
                    .id(query)
                    .padding(.horizontal, EmojiMetrics.searchMargin - inset)
                    .frame(height: max(results, 0))
                KeyArea(model: model, globe: globe, grid: grid, popupRoom: results)
            }
        }
    }

    /// Each emoji in the tone last picked for it, as the grid shows it.
    private var items: [EmojiItem] {
        guard let catalog = EmojiCatalog.bundled else { return [] }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return frequent.compactMap(catalog.lookup).map { EmojiItem(emoji: $0.emoji, tone: $0.tone) }
        }
        return catalog.search(query).map { emoji in
            EmojiItem(emoji: emoji, tone: catalog.lookup(history.shown(emoji))?.tone)
        }
    }

    private func pick(_ item: EmojiItem) {
        model.pick(item.glyph)
        history.use(item.emoji, tone: item.tone)
        history.store()
    }
}

/// The band at the top of the emoji page. On the grid it is a placeholder that opens search; in search it shows the
/// query and an ✕ that goes back to the grid. Either way `tap` is what it does.
struct EmojiSearchField: View {
    /// Nil on the grid, where nothing is being searched yet.
    let query: String?
    let tap: () -> Void

    /// Apple's field is lighter than the keyboard behind it, in both appearances.
    private static let fill = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 1, alpha: 0.5) })
    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        if let query {
            field(query)
        } else {
            Button(action: tap) { field(nil) }
                .buttonStyle(.plain)
                .accessibilityLabel("ค้นหาอีโมจิ")
        }
    }

    private func field(_ query: String?) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(.secondaryLabel))
            if let query, !query.isEmpty {
                Text(query)
                    .font(.loopless(17))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                    .truncationMode(.head)
                Caret()
            } else {
                if query != nil { Caret() }
                Text("ค้นหาอีโมจิ")
                    .font(.loopless(17))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if query != nil {
                Button(action: tap) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .feedbackOnKeyDown()
                .accessibilityLabel("ปิดการค้นหา")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, query == nil ? 16 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.fill, in: Self.shape)
        .contentShape(Self.shape)
    }
}

/// Where the next letter goes: the query has no other cursor.
private struct Caret: View {
    @State private var shown = true

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 22)
            .opacity(shown ? 1 : 0)
            .animation(.easeInOut(duration: 0.1).delay(0.4).repeatForever(), value: shown)
            .onAppear { shown = false }
            .accessibilityHidden(true)
    }
}

/// One row that scrolls sideways, as Apple's results do.
private struct EmojiResults: View {
    let items: [EmojiItem]
    let empty: String
    let pick: (EmojiItem) -> Void

    static let cell = CGSize(width: 46, height: 46)

    var body: some View {
        if items.isEmpty {
            Text(empty)
                .font(.loopless(15))
                .foregroundStyle(Color(.secondaryLabel))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button { pick(item) } label: {
                            Glyph(glyph: item.glyph)
                                .frame(width: Self.cell.width, height: Self.cell.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(EmojiPress())
                        .feedbackOnKeyDown()
                        .accessibilityLabel(item.emoji.name(tone: item.tone))
                        .accessibilityAddTraits(.isKeyboardKey)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct EmojiPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemGray3) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The grid's 2x glyph, so a long run of results costs what the grid does.
private struct Glyph: UIViewRepresentable {
    let glyph: String

    func makeUIView(context: Context) -> GlyphView { GlyphView() }

    func updateUIView(_ view: GlyphView, context: Context) { view.glyph = glyph }
}
