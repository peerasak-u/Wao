import Foundation
import WaoCore

/// The licences and notices of what the app ships or downloads, for its credits screen.
public enum Notice: CaseIterable, Hashable, Sendable {
    case openThaiASR, onnxRuntime, onnxRuntimeThirdParty, poodPim

    /// Read on demand: ONNX Runtime's third-party notices alone run to 341 KB.
    public func text() -> String {
        switch self {
        case .openThaiASR: Self.resource("OpenThai2.0-ASR-Streaming-LICENSE")
        case .onnxRuntime: Self.resource("onnxruntime-LICENSE")
        case .onnxRuntimeThirdParty: Self.resource("onnxruntime-ThirdPartyNotices")
        case .poodPim: BundledLists.notice
        }
    }

    private static func resource(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { preconditionFailure("\(name).txt missing from the WaoInference bundle; run tools/fetch_onnxruntime.sh") }
        // Microsoft's files have CRLF line endings.
        return text.replacingOccurrences(of: "\r\n", with: "\n")
    }
}
