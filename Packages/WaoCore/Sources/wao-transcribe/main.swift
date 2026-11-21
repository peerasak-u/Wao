import Foundation
import WaoCore
import WaoInference

let usage = """
    wao-transcribe [--model DIR] [--language th-TH|th-mix] [--decoding greedy|beam] [--no-cleanup] [--threads N]
        [--beam-width N] [--hotword-bonus X] [--beam-blank-bias X]
        [--deletion-guard SHARE | --no-deletion-guard] WAV...

    Prints one JSON line per file: file, text, tokens, audio_seconds, seconds (features + encoder + decoder),
    encoder_seconds, decoder_seconds. The model defaults to $WAO_MODEL_DIR or .model-cache/int8.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n\n\(usage)\n".utf8))
    exit(2)
}

var model = ProcessInfo.processInfo.environment["WAO_MODEL_DIR"] ?? ".model-cache/int8"
var language = Language.thaiEnglishMix
var decoding = Decoding.beam
var cleanup = TextCleanup.standard
var threads = 2
var beam = BeamSettings.poodPim
var files: [String] = []
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    func value<T>(_ parse: (String) -> T?) -> T {
        guard let v = args.popFirst().flatMap(parse) else { fail("\(arg) needs a valid value") }
        return v
    }
    switch arg {
    case "--model": model = value { $0 }
    case "--language": language = value(Language.init(rawValue:))
    case "--decoding": decoding = value(Decoding.init(rawValue:))
    case "--no-cleanup": cleanup = .none
    case "--threads": threads = value { Int($0) }
    case "--beam-width": beam.width = value { Int($0) }
    case "--hotword-bonus": beam.hotwordBonus = value { Float($0) }
    case "--beam-blank-bias": beam.blankBias = value { Float($0) }
    case "--deletion-guard": beam.deletionGuard = value { Double($0) }
    case "--no-deletion-guard": beam.deletionGuard = nil
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        if arg.hasPrefix("--") { fail("unknown option \(arg)") }
        files.append(arg)
    }
}
if files.isEmpty { fail("no wav files") }

struct Line: Encodable {
    let file: String
    let text: String
    let tokens: [Int]
    let audio_seconds: Double
    let seconds: Double
    let encoder_seconds: Double
    let decoder_seconds: Double
}

let transcriber = try Transcriber(modelDirectory: URL(fileURLWithPath: model), threads: threads, cleanup: cleanup, beam: beam)
let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
for file in files {
    let audio = try AudioFile.load16kMono(URL(fileURLWithPath: file))
    let r = try transcriber.transcribe(audio, language: language, decoding: decoding)
    let line = Line(file: file, text: r.text, tokens: r.tokens, audio_seconds: r.audioSeconds, seconds: r.totalSeconds,
                    encoder_seconds: r.encoderSeconds, decoder_seconds: r.decoderSeconds)
    print(String(decoding: try encoder.encode(line), as: UTF8.self))
}
