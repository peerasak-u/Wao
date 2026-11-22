import CoreText
import SwiftUI
import UIKit
import WaoTyping

/// A run of emoji under one header, and the bar icon that jumps to it.
enum EmojiTab: Hashable, CaseIterable {
    case frequent
    case category(EmojiCategory)

    static let allCases: [EmojiTab] = [.frequent] + EmojiCategory.allCases.map(EmojiTab.category)

    /// Uppercased on screen, as iOS shows them.
    var title: String {
        switch self {
        case .frequent: "Frequently Used"
        case .category(let category):
            switch category {
            case .smileys: "Smileys & People"
            case .animals: "Animals & Nature"
            case .food: "Food & Drink"
            case .activity: "Activity"
            case .travel: "Travel & Places"
            case .objects: "Objects"
            case .symbols: "Symbols"
            case .flags: "Flags"
            }
        }
    }

    /// The nearest SF Symbols, all on iOS 16, to the iOS emoji keyboard's category icons.
    var symbol: String {
        switch self {
        case .frequent: "clock"
        case .category(let category):
            switch category {
            case .smileys: "face.smiling"
            case .animals: "teddybear"
            case .food: "takeoutbag.and.cup.and.straw"
            case .activity: "soccerball"
            case .travel: "car"
            case .objects: "lightbulb"
            case .symbols: "music.note"
            case .flags: "flag"
            }
        }
    }
}

/// The iPhone emoji keyboard, one row per system generation and width class. It is taller than the typing keyboard,
/// so the extension grows while it shows; the page's frame (height, search band, bar) did not change in iOS 27, its
/// grid did: no section titles, four rows of larger emoji.
struct EmojiMetrics {
    enum System {
        case ios26, ios27

        static let current: System = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? .ios27 : .ios26
    }

    /// The extension's height on this page.
    let height: CGFloat
    /// From the bottom of the page to the middle of the category bar.
    let barMid: CGFloat
    let cell: CGSize
    let rows: Int
    /// Section titles' height; zero where the system shows none.
    let header: CGFloat
    /// From the top of the page to the grid's frame: the section titles, or the first row where there are none.
    let gridTop: CGFloat
    /// From the top of the page to the first row of cells.
    let rowsTop: CGFloat
    /// From the screen's edge to the first column's cells.
    let leading: CGFloat
    let glyph: CGFloat

    /// Apple's search field: its distance from the top of the page, its height and its distance from the screen's
    /// sides.
    static let searchTop: CGFloat = 10
    static let search: CGFloat = 40
    static let searchMargin: CGFloat = 9.6
    static let sectionGap: CGFloat = 20
    static let bar: CGFloat = 41

    /// A Pro Max class width gets the wide rows, as in `KeyMetrics`.
    init(width: CGFloat, system: System = .current) {
        switch (system, width >= 428) {
        // iOS 26.4, read off screenshots with tools/emoji_metrics.py on an iPhone 17e (390 pt).
        case (.ios26, false):
            self.init(height: 313, barMid: 21, cell: CGSize(width: 46, height: 38.5), rows: 5, header: 13,
                      gridTop: 62, rowsTop: 79.3, leading: 4.9, glyph: 32)
        // iOS 26.4 on an iPhone 17 Pro Max (440 pt).
        case (.ios26, true):
            self.init(height: 324, barMid: 26, cell: CGSize(width: 42, height: 40), rows: 5, header: 13,
                      gridTop: 59.7, rowsTop: 74.3, leading: 5.6, glyph: 32)
        // iOS 27 on a 393 pt iPhone, from a downscaled screenshot (±0.5 pt). The glyph's ink is 37 pt tall.
        case (.ios27, false):
            self.init(height: 313, barMid: 21, cell: CGSize(width: 54.2, height: 54.2), rows: 4, header: 0,
                      gridTop: 59.2, rowsTop: 59.2, leading: 13.65, glyph: 40.7)
        // Unmeasured: the 393 pt grid, raised by the 5 pt the iOS 26 rows rise between the two classes.
        case (.ios27, true):
            self.init(height: 324, barMid: 26, cell: CGSize(width: 54.2, height: 54.2), rows: 4, header: 0,
                      gridTop: 54.2, rowsTop: 54.2, leading: 13.65, glyph: 40.7)
        }
    }

    private init(height: CGFloat, barMid: CGFloat, cell: CGSize, rows: Int, header: CGFloat, gridTop: CGFloat,
                 rowsTop: CGFloat, leading: CGFloat, glyph: CGFloat) {
        self.height = height
        self.barMid = barMid
        self.cell = cell
        self.rows = rows
        self.header = header
        self.gridTop = gridTop
        self.rowsTop = rowsTop
        self.leading = leading
        self.glyph = glyph
    }

    /// From the top of the grid's frame to the first row of cells.
    var rowsBelowHeader: CGFloat { rowsTop - gridTop }
}

/// Where the user picks an emoji: the search field, a grid that scrolls sideways through the categories over a bar of
/// category icons, กขค back to the letters and delete, as on the iOS emoji keyboard.
struct EmojiPanel: View {
    @ObservedObject var model: KeyboardModel
    @State private var current: EmojiTab = .frequent
    @State private var jump: (tab: EmojiTab, serial: Int)?

    var body: some View {
        GeometryReader { geo in
            let screen = model.screenWidth ?? geo.size.width
            let inset = (screen - geo.size.width) / 2
            let metrics = EmojiMetrics(width: screen)
            VStack(spacing: 0) {
                EmojiSearchField(query: nil, tap: model.showEmojiSearch)
                    .frame(height: EmojiMetrics.search)
                    .padding(.horizontal, EmojiMetrics.searchMargin - inset)
                    .padding(.top, EmojiMetrics.searchTop)
                EmojiGrid(metrics: metrics, inset: inset, jump: jump, type: model.pick, scrolled: { current = $0 })
                    .padding(.top, metrics.gridTop - EmojiMetrics.searchTop - EmojiMetrics.search)
                bar(margin: KeyMetrics(width: screen).margin - inset)
                    .frame(height: EmojiMetrics.bar)
                    .padding(.bottom, metrics.barMid - EmojiMetrics.bar / 2)
            }
        }
    }

    /// Apple's ABC and delete sit in 54 pt slots at either end; the icons share what is left.
    private func bar(margin: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button(action: model.showLetters) {
                let style = KeyFont.label("กขค")
                Text("กขค").font(style.font).offset(y: style.lift)
                    .foregroundStyle(Color(.label))
                    .frame(width: 54, height: EmojiMetrics.bar)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .feedbackOnKeyDown()
            ForEach(EmojiTab.allCases, id: \.self) { tab in
                Button {
                    jump = (tab, (jump?.serial ?? 0) + 1)
                    current = tab
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(uiColor: tab == current ? .label : .secondaryLabel))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(uiColor: .label).opacity(tab == current ? 0.12 : 0)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .feedbackOnKeyDown()
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == current ? .isSelected : [])
            }
            DeleteKey(font: KeyFont.icon(narrow: false), insets: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8),
                      bare: true, action: model.deleteBackward)
                .frame(width: 54)
        }
        .padding(.horizontal, margin)
    }
}

/// The grid is UIKit: a collection view reuses its cells, so only the emoji on screen are drawn, and its highlight,
/// selection and scrolling already share touches the way a keyboard needs.
private struct EmojiGrid: UIViewRepresentable {
    let metrics: EmojiMetrics
    let inset: CGFloat
    let jump: (tab: EmojiTab, serial: Int)?
    let type: (String) -> Void
    let scrolled: (EmojiTab) -> Void

    func makeUIView(context: Context) -> EmojiGridView {
        EmojiGridView(catalog: EmojiCatalog.bundled, history: .stored, metrics: metrics)
    }

    func updateUIView(_ view: EmojiGridView, context: Context) {
        view.leadingInset = metrics.leading - inset
        view.onType = type
        view.onScroll = scrolled
        if let jump, jump.serial != view.jumpSerial {
            view.jumpSerial = jump.serial
            view.show(jump.tab)
        }
    }
}

/// An emoji cell: which emoji, and in which tone.
struct EmojiItem {
    let emoji: Emoji
    let tone: Int?

    var glyph: String { emoji.glyph(tone: tone) }
}

private final class EmojiGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    var onType: (String) -> Void = { _ in }
    var onScroll: (EmojiTab) -> Void = { _ in }
    var jumpSerial = 0
    var leadingInset: CGFloat = 0 {
        didSet {
            guard leadingInset != oldValue else { return }
            collection.contentInset = UIEdgeInsets(top: 0, left: leadingInset, bottom: 0, right: leadingInset)
            collection.contentOffset.x = -leadingInset
        }
    }

    private let catalog: EmojiCatalog?
    private var history: EmojiHistory
    /// Frequently used as it was when the panel opened, so nothing moves under the finger while picking.
    private let sections: [(tab: EmojiTab, items: [EmojiItem])]
    private let layout: EmojiGridLayout
    private let collection: UICollectionView
    private let picker = TonePicker()
    /// Catches the tap that closes the tone picker; nearly clear, since iOS hands touches on clear pixels to the host.
    private let catcher = UIView()
    private var pickerItem: IndexPath?
    private var lastTab: EmojiTab?

    init(catalog: EmojiCatalog?, history: EmojiHistory, metrics: EmojiMetrics) {
        self.catalog = catalog
        self.history = history
        let frequent = history.recent.compactMap { catalog?.lookup($0) }.map { EmojiItem(emoji: $0.emoji, tone: $0.tone) }
        let categories = (catalog?.sections ?? []).map { section in
            (tab: EmojiTab.category(section.category), items: section.emoji.map { EmojiItem(emoji: $0, tone: nil) })
        }
        sections = (frequent.isEmpty ? [] : [(tab: EmojiTab.frequent, items: frequent)]) + categories
        layout = EmojiGridLayout(counts: sections.map(\.items.count), titles: sections.map { $0.tab.title.uppercased() },
                                 metrics: metrics)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)

        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.alwaysBounceHorizontal = true
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.id)
        collection.register(EmojiHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                            withReuseIdentifier: EmojiHeader.id)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
        hold.minimumPressDuration = 0.35
        hold.delegate = self
        collection.addGestureRecognizer(hold)
        addSubview(collection)

        catcher.backgroundColor = UIColor(white: 0, alpha: 0.001)
        catcher.isHidden = true
        catcher.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closePicker)))
        addSubview(catcher)
        picker.isHidden = true
        picker.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickerTapped)))
        addSubview(picker)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        collection.frame = bounds
        catcher.frame = bounds
    }

    func show(_ tab: EmojiTab) {
        closePicker()
        let x = sections.firstIndex { $0.tab == tab }.map { layout.start(of: $0) } ?? 0
        let maxX = max(collection.contentSize.width - collection.bounds.width + leadingInset, -leadingInset)
        collection.setContentOffset(CGPoint(x: min(x - leadingInset, maxX), y: 0), animated: false)
        lastTab = tab
    }

    private func item(_ path: IndexPath) -> EmojiItem {
        let item = sections[path.section].items[path.item]
        guard case .category = sections[path.section].tab,
              let shown = catalog?.lookup(history.shown(item.emoji)) else { return item }
        return EmojiItem(emoji: shown.emoji, tone: shown.tone)
    }

    /// A new tone shows at once in the categories; frequently used waits for the next time the panel opens.
    private func type(_ item: EmojiItem) {
        let shown = history.shown(item.emoji)
        onType(item.glyph)
        history.use(item.emoji, tone: item.tone)
        history.store()
        if history.shown(item.emoji) != shown { collection.reloadData() }
    }

    // MARK: Data source

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.id, for: path) as! EmojiCell
        let item = item(path)
        cell.show(item.glyph, name: item.emoji.name(tone: item.tone), size: layout.glyph)
        cell.accessibilityCustomActions = item.emoji.tones.indices.map { tone in
            UIAccessibilityCustomAction(name: Emoji.toneNames[tone]) { [weak self] _ in
                self?.type(EmojiItem(emoji: item.emoji, tone: tone))
                return true
            }
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at path: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: EmojiHeader.id,
                                                                     for: path) as! EmojiHeader
        header.label.text = sections[path.section].tab.title.uppercased()
        return header
    }

    // MARK: Touches

    /// A finger landing on an emoji, after the scroll view's short wait to see whether it is a swipe.
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt path: IndexPath) {
        KeyFeedback.shared.keyDown()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt path: IndexPath) {
        collectionView.deselectItem(at: path, animated: false)
        type(item(path))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !sections.isEmpty else { return }
        let tab = sections[layout.section(at: scrollView.contentOffset.x + leadingInset + 1)].tab
        if tab != lastTab {
            lastTab = tab
            // The first report comes from SwiftUI's own update, which drops state changed during it.
            DispatchQueue.main.async { self.onScroll(tab) }
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { closePicker() }

    /// Only emoji that come in skin tones answer a long press; the rest type on release as usual.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer.view === collection else { return super.gestureRecognizerShouldBegin(recognizer) }
        guard let path = collection.indexPathForItem(at: recognizer.location(in: collection)) else { return false }
        return !item(path).emoji.tones.isEmpty
    }

    /// Hold, then slide onto a tone and lift to type it, or lift in place and tap one, as on iOS.
    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard let path = collection.indexPathForItem(at: recognizer.location(in: collection)),
                  let cell = collection.cellForItem(at: path) else { return }
            let item = item(path)
            pickerItem = path
            picker.show(item.emoji, chosen: item.tone, over: cell.convert(cell.bounds, to: self), in: bounds)
            catcher.isHidden = false
            KeyFeedback.shared.keyDown()
        case .changed:
            picker.track(recognizer.location(in: picker))
        case .ended:
            if let tone = picker.armedChoice { choose(tone) }
        case .cancelled, .failed:
            closePicker()
        default:
            break
        }
    }

    @objc private func pickerTapped(_ recognizer: UITapGestureRecognizer) {
        if let tone = picker.choice(at: recognizer.location(in: picker)) { choose(tone) }
    }

    private func choose(_ tone: Int?) {
        guard let path = pickerItem else { return }
        type(EmojiItem(emoji: item(path).emoji, tone: tone))
        closePicker()
    }

    @objc private func closePicker() {
        picker.isHidden = true
        catcher.isHidden = true
        pickerItem = nil
    }
}

/// Emoji in columns of `rows`, sections side by side with a gap, each under its header where the system draws one.
/// Every frame is worked out once, since the catalog never changes while the panel is open.
private final class EmojiGridLayout: UICollectionViewLayout {
    private var items: [[UICollectionViewLayoutAttributes]] = []
    private var headers: [UICollectionViewLayoutAttributes] = []
    private var starts: [CGFloat] = []
    private var width: CGFloat = 0
    private let height: CGFloat
    private let showsHeaders: Bool
    let glyph: CGFloat

    init(counts: [Int], titles: [String], metrics: EmojiMetrics) {
        let cell = metrics.cell, rows = metrics.rows
        showsHeaders = metrics.header > 0
        glyph = metrics.glyph
        height = metrics.rowsBelowHeader + CGFloat(rows) * cell.height
        super.init()
        let font = EmojiHeader.font
        var x: CGFloat = 0
        for (section, count) in counts.enumerated() {
            starts.append(x)
            items.append((0..<count).map { i in
                let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: i, section: section))
                attributes.frame = CGRect(x: x + CGFloat(i / rows) * cell.width, y: metrics.rowsBelowHeader + CGFloat(i % rows) * cell.height,
                                          width: cell.width, height: cell.height)
                return attributes
            })
            let title = showsHeaders ? (titles[section] as NSString).size(withAttributes: [.font: font]).width : 0
            let columns = CGFloat((count + rows - 1) / rows)
            let header = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                                          with: IndexPath(item: 0, section: section))
            header.frame = CGRect(x: x, y: 0, width: max(columns * cell.width, title + 8), height: metrics.header)
            headers.append(header)
            x += header.frame.width + EmojiMetrics.sectionGap
        }
        width = max(x - EmojiMetrics.sectionGap, 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func start(of section: Int) -> CGFloat { starts[section] }

    /// The section under content offset `x`.
    func section(at x: CGFloat) -> Int { max(starts.lastIndex { $0 <= x } ?? 0, 0) }

    override var collectionViewContentSize: CGSize {
        // Only sideways: the last row's cell may run a fraction of a point past the bar's top.
        CGSize(width: width, height: min(height, collectionView?.bounds.height ?? height))
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var found = showsHeaders ? headers.filter { $0.frame.intersects(rect) } : []
        for (section, start) in starts.enumerated() where start <= rect.maxX && headers[section].frame.maxX >= rect.minX {
            found += items[section].filter { $0.frame.intersects(rect) }
        }
        return found
    }

    override func layoutAttributesForItem(at path: IndexPath) -> UICollectionViewLayoutAttributes? {
        items[path.section][path.item]
    }

    override func layoutAttributesForSupplementaryView(ofKind kind: String, at path: IndexPath) -> UICollectionViewLayoutAttributes? {
        headers[path.section]
    }
}

private final class EmojiCell: UICollectionViewCell {
    static let id = "emoji"
    private let label = GlyphView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 8
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds.insetBy(dx: 1, dy: 0)
        label.frame = contentView.bounds
    }

    func show(_ glyph: String, name: String, size: CGFloat) {
        label.size = size
        label.glyph = glyph
        accessibilityLabel = name
    }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? .systemGray3 : nil }
    }
}

/// The font the emoji page draws with. CoreText keeps the image of every emoji a font has drawn for as long as the
/// font lives, and the system font's emoji fallback lives as long as the keyboard's process, which iOS keeps across
/// host apps: a walk through every category left 30 MB behind after the page closed. A font made from the emoji
/// file's own `CGFont` belongs to the page alone; the controller drops it when the page closes, and its images go with
/// the page's views. Falls back to the system font if the file won't open.
@MainActor
enum EmojiFace {
    /// The font, and the system font's line for one emoji with how far that line's ink sits from this font's. Every
    /// emoji has the same advance, so one measures them all.
    struct Face {
        let font: UIFont
        fileprivate let width: CGFloat
        fileprivate let ascent: CGFloat
        fileprivate let descent: CGFloat
        fileprivate let shift: CGPoint

        /// Where the line starts, in a flipped context, for its ink to land where UIKit's centred system font line
        /// would put it. UIKit's string drawing puts the baseline on a whole pixel.
        func origin(in box: CGSize, scale: CGFloat) -> CGPoint {
            let baseline = (box.height - ascent - descent) / 2 + descent + shift.y
            return CGPoint(x: (box.width - width) / 2 + shift.x, y: (baseline * scale).rounded() / scale)
        }
    }

    private static var faces: [CGFloat: Face] = [:]

    static func face(_ size: CGFloat) -> Face {
        if let face = faces[size] { return face }
        let system = UIFont.systemFont(ofSize: size)
        let font = file(size) ?? system
        let placed = line("😀", font: system)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(placed, &ascent, &descent, nil)
        let ink = CTLineGetImageBounds(placed, nil)
        let own = CTLineGetImageBounds(line("😀", font: font), nil)
        let face = Face(font: font, width: width, ascent: ascent, descent: descent,
                        shift: CGPoint(x: ink.midX - own.midX, y: ink.midY - own.midY))
        faces[size] = face
        return face
    }

    static func drop() { faces = [:] }

    static func line(_ glyph: String, font: UIFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: [.font: font]))
    }

    private static func file(_ size: CGFloat) -> UIFont? {
        let system = CTFontCreateWithName("AppleColorEmoji" as CFString, size, nil)
        guard let url = CTFontCopyAttribute(system, kCTFontURLAttribute) as? URL,
              let provider = CGDataProvider(url: url as CFURL),
              let file = CGFont(provider) else { return nil }
        return CTFontCreateWithGraphicsFont(file, size, nil, nil) as UIFont
    }
}

/// One emoji, drawn at no more than 64 pixels a side, 2x for the 32 pt grid even on a 3x screen. CoreText keeps each
/// image from the font's bitmap one size up: 48 KB at 32 pt and 3x, 16 KB at 2x, measured in the iOS 26.4 simulator.
/// iOS 27's 40.7 pt glyphs at 2x took the next bitmap up, so they draw at 64 pixels too.
final class GlyphView: UIView {
    private static let pixels: CGFloat = 64

    var size: CGFloat = 32 {
        didSet {
            guard size != oldValue else { return }
            layer.contentsScale = scale
            setNeedsDisplay()
        }
    }

    private var scale: CGFloat { min(UIScreen.main.scale, Self.pixels / size) }

    var glyph = "" {
        didSet { if glyph != oldValue { setNeedsDisplay() } }
    }

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// UIKit sets the screen's scale when the view joins a window, so it is put back after.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        layer.contentsScale = scale
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let face = EmojiFace.face(size)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = face.origin(in: bounds.size, scale: layer.contentsScale)
        CTLineDraw(EmojiFace.line(glyph, font: face.font), context)
    }
}

private final class EmojiHeader: UICollectionReusableView {
    static let id = "header"
    static let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = Self.font
        label.textColor = .secondaryLabel
        label.accessibilityTraits = .header
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 4, dy: 0)
    }
}

/// The skin tones of one emoji in a row: the default yellow, then light to dark.
private final class TonePicker: UIView {
    private static let option = CGSize(width: 42, height: 46)
    private var labels: [GlyphView] = []
    private var tones: [Int?] = []
    /// The option the finger is on, once it has slid onto the picker.
    private(set) var armedChoice: Int??

    init() {
        super.init(frame: .zero)
        backgroundColor = Key.fillColor
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Above the emoji, or below it on the top row, where above is off the keyboard.
    func show(_ emoji: Emoji, chosen: Int?, over cell: CGRect, in bounds: CGRect) {
        labels.forEach { $0.removeFromSuperview() }
        tones = [nil] + emoji.tones.indices.map { $0 }
        labels = tones.enumerated().map { i, tone in
            let label = GlyphView(frame: CGRect(x: CGFloat(i) * Self.option.width, y: 0, width: Self.option.width, height: Self.option.height))
            label.glyph = emoji.glyph(tone: tone)
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            label.isAccessibilityElement = true
            label.accessibilityLabel = emoji.name(tone: tone)
            addSubview(label)
            return label
        }
        let size = CGSize(width: Self.option.width * CGFloat(tones.count), height: Self.option.height)
        let x = min(max(cell.midX - size.width / 2, bounds.minX + 2), bounds.maxX - size.width - 2)
        let y = cell.minY - size.height - 2 >= bounds.minY ? cell.minY - size.height - 2 : cell.maxY + 2
        frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        armedChoice = nil
        mark(tones.firstIndex(of: chosen))
        isHidden = false
    }

    func track(_ point: CGPoint) {
        guard bounds.insetBy(dx: 0, dy: -24).contains(point), let i = index(at: point.x) else { return }
        armedChoice = tones[i]
        mark(i)
    }

    func choice(at point: CGPoint) -> Int?? {
        index(at: point.x).map { tones[$0] }
    }

    private func index(at x: CGFloat) -> Int? {
        let i = Int(x / Self.option.width)
        return tones.indices.contains(i) ? i : nil
    }

    private func mark(_ index: Int?) {
        for (i, label) in labels.enumerated() { label.backgroundColor = i == index ? .systemGray4 : .clear }
    }
}

extension EmojiHistory {
    private static let key = "emojiHistory"

    /// The extension's own defaults, which need no Full Access.
    static var stored: EmojiHistory {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(EmojiHistory.self, from: $0) } ?? EmojiHistory()
    }

    func store() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
