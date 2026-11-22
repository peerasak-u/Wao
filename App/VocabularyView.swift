import SwiftUI
import WaoCore

/// PoodPim's tuning found 150-350 words works best; past that the beam starts writing terms nobody said.
private let comfortableWordCount = 350

struct VocabularyCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let book = model.vocabulary
        NavigationLink(value: VocabularyRoute.book) {
            HStack(spacing: 14) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("คลังคำศัพท์").font(.loopless(16, .medium))
                    Text("\(book.effectiveWords.count) คำ · เปิด \(book.enabledGroupCount) จาก \(book.groups.count) กลุ่ม")
                        .font(.loopless(13).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
        .accessibilityIdentifier("vocabulary-card")
    }
}

enum VocabularyRoute: Hashable {
    case book
    case group(VocabularyGroup.ID)

    @ViewBuilder var screen: some View {
        switch self {
        case .book: VocabularyScreen()
        case .group(let id): GroupScreen(id: id)
        }
    }
}

extension VocabularyBook {
    var enabledGroupCount: Int { groups.filter(\.isEnabled).count }

    func index(of id: VocabularyGroup.ID) -> Int? { groups.firstIndex { $0.id == id } }
}

struct VocabularyScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var importing = false
    @State private var naming = false
    @State private var confirmingReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary
                SearchField(text: $query)
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    groups
                } else {
                    results
                }
                Button("คืนค่าเริ่มต้น") { confirmingReset = true }
                    .font(.loopless(14))
                    .foregroundStyle(Palette.tertiary)
                    .confirmationDialog("คืนคลังคำศัพท์เป็นค่าเริ่มต้น?", isPresented: $confirmingReset, titleVisibility: .visible) {
                        Button("คืนค่าเริ่มต้น", role: .destructive) { model.vocabulary = .bundled }
                    } message: {
                        Text("กลุ่มและคำที่เพิ่มหรือแก้ไว้จะหายทั้งหมด")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("คลังคำศัพท์")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $importing) { ImportSheet(initialTarget: nil) }
        .sheet(isPresented: $naming) {
            NameSheet(title: "กลุ่มใหม่", placeholder: "ชื่อกลุ่ม", initial: "", action: "สร้าง") { name in
                model.vocabulary.groups.insert(VocabularyGroup(name: name), at: 0)
            }
        }
    }

    private var summary: some View {
        let book = model.vocabulary
        let count = book.effectiveWords.count
        return VStack(alignment: .leading, spacing: 16) {
            Text("คำภาษาอังกฤษที่อยากให้เขียนเป็นตัวอักษรอังกฤษ เช่น ชื่อบริษัท ชื่อสินค้า ศัพท์ที่ใช้บ่อย")
                .font(.loopless(14))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(count)").font(.loopless(44, .bold).monospacedDigit())
                Text("คำที่ใช้อยู่").font(.loopless(15)).foregroundStyle(Palette.secondary)
                Spacer()
                Text("เปิด \(book.enabledGroupCount) จาก \(book.groups.count) กลุ่ม")
                    .font(.loopless(14).monospacedDigit())
                    .foregroundStyle(Palette.secondary)
            }
            if count > comfortableWordCount {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.top, 2)
                    Text("เกิน \(comfortableWordCount) คำ รายการที่ยาวอาจทำให้โมเดลใส่คำที่คุณไม่ได้พูด ลองปิดกลุ่มที่ไม่ค่อยได้ใช้")
                        .font(.loopless(13))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.55))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1, green: 0.75, blue: 0.3).opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(spacing: 10) {
                PillButton(title: "นำเข้าหลายคำ") { importing = true }
                PillButton(title: "กลุ่มใหม่") { naming = true }
            }
        }
    }

    private var groups: some View {
        VStack(spacing: 10) {
            ForEach($model.vocabulary.groups) { $group in
                HStack(spacing: 0) {
                    NavigationLink(value: VocabularyRoute.group(group.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.loopless(16, .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("\(group.words.count) คำ")
                                .font(.loopless(13).monospacedDigit())
                                .foregroundStyle(Palette.secondary)
                        }
                        .opacity(group.isEnabled ? 1 : 0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Toggle(group.name, isOn: $group.isEnabled)
                        .toggleStyle(GlowSwitch())
                        .padding(.trailing, 18)
                }
                .card()
            }
        }
    }

    private var results: some View {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let hits = model.vocabulary.groups.flatMap { group in
            group.words.filter { $0.localizedCaseInsensitiveContains(needle) }.map { (word: $0, group: group) }
        }
        return VStack(alignment: .leading, spacing: 0) {
            if hits.isEmpty {
                Text("ไม่พบ \"\(needle)\"")
                    .font(.loopless(14))
                    .foregroundStyle(Palette.secondary)
                    .padding(18)
            }
            ForEach(Array(hits.enumerated()), id: \.offset) { i, hit in
                if i > 0 { Divider().overlay(Palette.hairline).padding(.leading, 18) }
                NavigationLink(value: VocabularyRoute.group(hit.group.id)) {
                    HStack {
                        Text(hit.word).font(.loopless(16))
                        Spacer()
                        Text(hit.group.name)
                            .font(.loopless(13))
                            .foregroundStyle(Palette.tertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

private struct GroupScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let id: VocabularyGroup.ID
    @State private var newWord = ""
    @State private var notice: String?
    @State private var editing: Int?
    @State private var renaming = false
    @State private var importing = false
    @State private var confirmingDelete = false

    var body: some View {
        if let i = model.vocabulary.index(of: id) {
            content(model.vocabulary.groups[i], $model.vocabulary.groups[i])
        } else {
            Color.clear.screenBackground()
        }
    }

    private func content(_ group: VocabularyGroup, _ binding: Binding<VocabularyGroup>) -> some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.isEnabled ? "ใช้อยู่" : "ปิดอยู่").font(.loopless(16, .medium))
                        Text("\(group.words.count) คำ").font(.loopless(13).monospacedDigit()).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Toggle(group.name, isOn: binding.isEnabled).toggleStyle(GlowSwitch())
                }
                .padding(.vertical, 4)
                HStack(spacing: 10) {
                    TextField("", text: $newWord, prompt: Text("เพิ่มคำ (คั่นหลายคำด้วย ,)").foregroundStyle(Palette.tertiary))
                        .font(.loopless(16))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 24))
                    }
                    .buttonStyle(.plain)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(newWord.trimmingCharacters(in: .whitespaces).isEmpty ? 0.3 : 1)
                }
                if let notice {
                    Text(notice).font(.loopless(13)).foregroundStyle(Palette.secondary)
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                ForEach(Array(group.words.enumerated()), id: \.offset) { i, word in
                    Button { editing = i } label: {
                        Text(word).font(.loopless(16)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { binding.wrappedValue.words.remove(atOffsets: $0) }
                .listRowBackground(Color.white.opacity(0.04))
            } header: {
                Text("แตะเพื่อแก้ · ปัดซ้ายเพื่อลบ").font(.loopless(13)).foregroundStyle(Palette.tertiary).textCase(nil)
            }

            Section {
                HStack(spacing: 10) {
                    PillButton(title: "นำเข้าหลายคำ") { importing = true }
                    PillButton(title: "เปลี่ยนชื่อ") { renaming = true }
                    Spacer()
                    Button("ลบกลุ่ม") { confirmingDelete = true }
                        .font(.loopless(14, .medium))
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.42))
                        .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .listRowSeparatorTint(Palette.hairline)
        .environment(\.defaultMinListRowHeight, 48)
        .screenBackground()
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $importing) { ImportSheet(initialTarget: id) }
        .sheet(isPresented: $renaming) {
            NameSheet(title: "เปลี่ยนชื่อกลุ่ม", placeholder: "ชื่อกลุ่ม", initial: group.name, action: "บันทึก") {
                binding.wrappedValue.name = $0
            }
        }
        .sheet(item: Binding(get: { editing.map(EditedWord.init) }, set: { editing = $0?.index })) { edited in
            NameSheet(title: "แก้คำ", placeholder: "คำ", initial: group.words[edited.index], action: "บันทึก") {
                binding.wrappedValue.words[edited.index] = $0
            }
        }
        .confirmationDialog("ลบกลุ่ม \"\(group.name)\"?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("ลบ \(group.words.count) คำ", role: .destructive) {
                dismiss()
                model.vocabulary.groups.removeAll { $0.id == id }
            }
        }
    }

    private func add() {
        let preview = model.vocabulary.previewImport(newWord)
        model.vocabulary.importWords(newWord, into: id)
        notice = preview.duplicates.isEmpty ? nil : "มีอยู่แล้ว: \(preview.duplicates.joined(separator: ", "))"
        newWord = ""
    }
}

private struct EditedWord: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct ImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var target: VocabularyGroup.ID?
    @State private var newGroupName = ""
    @FocusState private var editorFocused: Bool

    init(initialTarget: VocabularyGroup.ID?) {
        _target = State(initialValue: initialTarget)
    }

    var body: some View {
        let preview = model.vocabulary.previewImport(text)
        let ready = !preview.added.isEmpty && (target != nil || !newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("ใส่ในกลุ่ม") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                Chip(title: "＋ กลุ่มใหม่", selected: target == nil) { target = nil }
                                ForEach(model.vocabulary.groups) { group in
                                    Chip(title: group.name, selected: target == group.id) { target = group.id }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                        .padding(.horizontal, -20)
                        if target == nil {
                            TextField("", text: $newGroupName, prompt: Text("ชื่อกลุ่มใหม่").foregroundStyle(Palette.tertiary))
                                .font(.loopless(16))
                                .padding(14)
                                .card()
                        }
                    }
                    section("คำ") {
                        ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("วางคำที่คั่นด้วย , หรือขึ้นบรรทัดใหม่\nเช่น Supabase, Vercel, Figma")
                                    .font(.loopless(16))
                                    .foregroundStyle(Palette.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $text)
                                .font(.loopless(16))
                                .scrollContentBackground(.hidden)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($editorFocused)
                        }
                        .frame(minHeight: 130)
                        .padding(10)
                        .card()
                    }
                    if !text.isEmpty {
                        section("ตัวอย่าง") {
                            FlowLayout(spacing: 6) {
                                ForEach(Array(preview.added.enumerated()), id: \.offset) { _, word in
                                    Text(word)
                                        .font(.loopless(14))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.white.opacity(0.1), in: Capsule())
                                }
                                ForEach(Array(preview.duplicates.enumerated()), id: \.offset) { _, word in
                                    Text(word)
                                        .font(.loopless(14))
                                        .strikethrough()
                                        .foregroundStyle(Palette.tertiary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                                }
                            }
                        }
                            }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if !text.isEmpty {
                        Text("เพิ่ม \(preview.added.count) คำ · ซ้ำ \(preview.duplicates.count) คำ")
                            .font(.loopless(14).monospacedDigit())
                            .foregroundStyle(Palette.secondary)
                            .accessibilityIdentifier("import-summary")
                    }
                    Button { commit(); dismiss() } label: {
                    Text(preview.added.isEmpty ? "เพิ่มคำ" : "เพิ่ม \(preview.added.count) คำ")
                        .font(.loopless(18, .semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(ready ? Palette.canvas : Palette.tertiary)
                        .background(Capsule().fill(ready ? Color.white : Color.white.opacity(0.08)))
                }
                    .buttonStyle(Pressable())
                    .disabled(!ready)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Palette.canvas.opacity(0.96))
            }
            .screenBackground()
            .navigationTitle("นำเข้าหลายคำ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationBackground(Palette.canvas)
        .onAppear { editorFocused = true }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.loopless(13, .medium)).foregroundStyle(Palette.tertiary)
            content()
        }
    }

    private func commit() {
        let id: VocabularyGroup.ID
        if let target {
            id = target
        } else {
            let group = VocabularyGroup(name: newGroupName.trimmingCharacters(in: .whitespaces))
            model.vocabulary.groups.insert(group, at: 0)
            id = group.id
        }
        model.vocabulary.importWords(text, into: id)
    }
}

private struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.loopless(14, selected ? .semibold : .text))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .foregroundStyle(selected ? Palette.canvas : .white)
                .background(selected ? Color.white : Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0 : 0.14), lineWidth: 1))
        }
        .buttonStyle(Pressable())
    }
}

/// A sheet rather than an alert, so the field and its labels are in Sukhumvit Set like the rest of the app.
private struct NameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    let action: String
    let save: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(title: String, placeholder: String, initial: String, action: String, save: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.action = action
        self.save = save
        _text = State(initialValue: initial)
    }

    var body: some View {
        let value = text.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.loopless(20, .semibold))
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.tertiary))
                .font(.loopless(17))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { if !value.isEmpty { save(value); dismiss() } }
                .padding(14)
                .card()
            HStack(spacing: 10) {
                Button("ยกเลิก") { dismiss() }
                    .font(.loopless(16, .medium))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(.white.opacity(0.06), in: Capsule())
                Button(action) { save(value); dismiss() }
                    .font(.loopless(16, .semibold))
                    .foregroundStyle(Palette.canvas)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(.white))
                    .disabled(value.isEmpty)
                    .opacity(value.isEmpty ? 0.35 : 1)
            }
            .buttonStyle(Pressable())
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .presentationDetents([.height(250)])
        .presentationBackground(Color(white: 0.09))
        .onAppear { focused = true }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.tertiary)
            TextField("", text: $text, prompt: Text("ค้นหาคำในทุกกลุ่ม").foregroundStyle(Palette.tertiary))
                .font(.loopless(16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

/// The system switch's white knob vanishes on a white track; this one inverts the knob when on.
struct GlowSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Color.white : Color.white.opacity(0.12))
                .overlay(Capsule().strokeBorder(.white.opacity(configuration.isOn ? 0 : 0.16), lineWidth: 1))
                .frame(width: 50, height: 30)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Palette.canvas : Color.white.opacity(0.7))
                        .padding(4)
                }
                .shadow(color: .white.opacity(configuration.isOn ? 0.3 : 0), radius: 8)
                .animation(.snappy(duration: 0.2), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .init(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !current.items.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = ([], current.y + current.height + spacing, 0, 0)
            }
            current.width += (current.items.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.items.append(i)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
