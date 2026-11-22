import SwiftUI
import WaoInference

enum CreditsRoute: Hashable {
    case credits
    case licence(Notice)

    @ViewBuilder var screen: some View {
        switch self {
        case .credits: CreditsScreen()
        case .licence(let notice): LicenceScreen(notice: notice)
        }
    }
}

/// On the main screen itself, so the model's makers are credited without anyone opening a menu.
struct CreditsFooter: View {
    var body: some View {
        NavigationLink(value: CreditsRoute.credits) {
            VStack(spacing: 6) {
                Text("ถอดเสียงด้วย OpenThai2.0-ASR · iApp Technology")
                    .foregroundStyle(Palette.secondary)
                Text("เครดิตและสัญญาอนุญาต")
                    .foregroundStyle(.white)
                    .underline()
            }
            .font(.loopless(13))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .accessibilityIdentifier("credits-footer")
    }
}

private struct CreditsScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModelCredit()
                Credit(
                    title: "ONNX Runtime 1.32.0",
                    byline: "Microsoft · MIT",
                    detail: "รันโมเดลบนเครื่อง ฝังอยู่ในแอป",
                    links: [
                        .web("NuGet · Microsoft.ML.OnnxRuntime", "https://www.nuget.org/packages/Microsoft.ML.OnnxRuntime/1.32.0"),
                        .licence("สัญญาอนุญาต MIT", .onnxRuntime),
                        .licence("Third-party notices", .onnxRuntimeThirdParty),
                    ]
                )
                Credit(
                    title: "PoodPim",
                    byline: "Thirawat Sutalungka · MIT",
                    detail: "การถอดรหัส การเกลาข้อความ และรายการคำเริ่มต้น ดัดแปลงมาจาก PoodPim",
                    links: [
                        .web("GitHub", "https://github.com/thirawat/PoodPim"),
                        .licence("สัญญาอนุญาต MIT", .poodPim),
                    ]
                )
                Credit(
                    title: "ข้อความภาษาไทยสำหรับแป้นพิมพ์",
                    byline: "Common Voice · wisesight-sentiment · PyThaiNLP · CC0",
                    detail: "แป้นพิมพ์ใช้สถิติตัวอักษรและรายการคำจากข้อความเหล่านี้ เพื่อเดาปุ่มที่ตั้งใจกดและแนะนำคำ",
                    links: [
                        .web("Common Voice", "https://github.com/common-voice/common-voice"),
                        .web("wisesight-sentiment", "https://github.com/PyThaiNLP/wisesight-sentiment"),
                        .web("PyThaiNLP", "https://github.com/PyThaiNLP/pythainlp"),
                    ]
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle("เครดิต")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ModelCredit: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("โมเดลถอดเสียง")
                    .font(.loopless(13, .medium))
                    .foregroundStyle(Palette.tertiary)
                Text("OpenThai2.0-ASR-Streaming")
                    .font(.loopless(24, .bold))
                    .shadow(color: .white.opacity(0.25), radius: 16)
                Text("โดย iApp Technology")
                    .font(.loopless(15, .medium))
                    .foregroundStyle(Palette.secondary)
            }
            Text("ขอบคุณ iApp Technology และ AIEAT ที่เปิดโมเดลถอดเสียงภาษาไทยให้ใช้ฟรี")
                .font(.loopless(17, .medium))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Fact("ผู้พัฒนา", "iApp Technology (iApp) เปิดตัวร่วมกับ AIEAT")
                Fact("โครงการ", "OpenThai (เดิมคือ OpenThaiGPT)")
                Fact("พื้นฐาน", "Nemotron ASR streaming ของ NVIDIA")
                Fact("ไฟล์ที่ใช้", "iapp/OpenThai2.0-ASR-Streaming-ONNX (int8) ดาวน์โหลดตอนตั้งค่า ไม่ได้รวมไว้ในแอป")
                Fact("สัญญาอนุญาต", "OpenMDW-1.1")
            }
            Links(links: [
                .web("Hugging Face · ONNX", "https://huggingface.co/iapp/OpenThai2.0-ASR-Streaming-ONNX"),
                .web("Hugging Face · NeMo", "https://huggingface.co/iapp/OpenThai2.0-ASR-Streaming"),
                .web("OpenMDW-1.1 · openmdw.ai", "https://openmdw.ai/license/1-1/"),
                .licence("สัญญาอนุญาตและที่มา", .openThaiASR),
            ])
        }
        .padding(20)
        .card(lit: true)
    }
}

private struct Fact: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(Palette.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.loopless(14))
    }
}

private struct Credit: View {
    let title: String
    let byline: String
    let detail: String
    let links: [CreditLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.loopless(17, .semibold))
                Text(byline).font(.loopless(14)).foregroundStyle(Palette.secondary)
            }
            Text(detail)
                .font(.loopless(14))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Links(links: links)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private enum CreditLink: Hashable {
    case web(String, String)
    case licence(String, Notice)
}

private struct Links: View {
    let links: [CreditLink]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(links, id: \.self) { link in
                Divider().overlay(Palette.hairline)
                switch link {
                case .web(let title, let address):
                    Link(destination: URL(string: address)!) { row(title, symbol: "arrow.up.right") }
                        .accessibilityIdentifier(address)
                case .licence(let title, let notice):
                    NavigationLink(value: CreditsRoute.licence(notice)) { row(title, symbol: "chevron.right") }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, symbol: String) -> some View {
        HStack {
            Text(title).font(.loopless(15, .medium))
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tertiary)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct LicenceScreen: View {
    let notice: Notice
    @State private var paragraphs: [String]?

    var body: some View {
        ScrollView {
            if let paragraphs {
                // Lazy so ONNX Runtime's 6,000-line notices lay out only as they scroll into view.
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(paragraphs.indices, id: \.self) { i in
                        Text(paragraphs[i])
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            } else {
                ProgressView().tint(.white).padding(.top, 60)
            }
        }
        .screenBackground()
        .navigationTitle(notice.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let notice = notice
            paragraphs = await Task.detached { notice.text().components(separatedBy: "\n\n").map(reflow) }.value
        }
    }
}

/// The texts are hard-wrapped near 80 columns, about twice what fits on a phone, so every line would break
/// twice. A line rejoins a long line before it when it is indented at least as deep and is not a list item;
/// short lines (addresses, headings) keep their own line.
private func reflow(_ paragraph: String) -> String {
    var result = ""
    var previous: (length: Int, indent: Int)?
    for line in paragraph.split(separator: "\n", omittingEmptySubsequences: false) {
        let body = line.drop { $0.isWhitespace }
        let indent = line.count - body.count
        let isListItem = body.range(of: #"^([-*•]|\(?[0-9a-zA-Z]{1,3}[.)])\s"#, options: .regularExpression) != nil
        if let run = previous, run.length >= 50, indent >= run.indent, !body.isEmpty, !isListItem {
            result += " " + body
            previous = (line.count, run.indent)
        } else {
            if previous != nil { result += "\n" }
            result += line
            previous = (line.count, indent)
        }
    }
    return result
}

private extension Notice {
    var title: String {
        switch self {
        case .openThaiASR: "OpenThai2.0-ASR · OpenMDW-1.1"
        case .onnxRuntime: "ONNX Runtime · MIT"
        case .onnxRuntimeThirdParty: "ONNX Runtime · Third-party"
        case .poodPim: "PoodPim · MIT"
        }
    }
}
