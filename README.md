# เว่า

Offline Thai dictation keyboard for iOS. The keyboard extension is UI only; the app holds the mic and runs
iapp/OpenThai2.0-ASR-Streaming-ONNX (int8) on the CPU with ONNX Runtime.

## Build

```sh
tools/fetch_onnxruntime.sh   # ONNX Runtime 1.32.0 xcframework from Microsoft's NuGet package, pinned by hash
xcodegen generate            # Wao.xcodeproj from project.yml
open Wao.xcodeproj
```

## Test

```sh
cd Packages/WaoCore && swift test     # model tests skip unless .model-cache/int8 holds the model
```

To run the model tests, put `encoder.int8.onnx.data` and the extracted `.asr.zip` in `.model-cache/int8`.
`tools/reference_transcribe.py` is the Python reference the Swift fixtures in
`Packages/WaoCore/Tests/WaoCoreTests/Fixtures` come from; `tools/make_samples.sh` regenerates `samples/`.

## Evaluate

```sh
cd Packages/WaoCore && swift build -c release --product wao-transcribe
.build/release/wao-transcribe --language th-mix --decoding beam ../../samples/*.wav   # JSON lines: file, text, seconds
```

`tools/asr_eval.py` runs it over PoodPim's Thai/English eval set and writes results its `eval.py report` scores.
`tools/reference_beam.py` is PoodPim's beam search transcribed to Python on the reference encoder; its tokens match
the Swift beam's exactly (`wao-transcribe` prints `tokens` too).

## Credits

The beam search with hotword biasing, the text clean-up and the default vocabulary and corrections lists are adapted
from [PoodPim](https://github.com/thirawat/PoodPim) (MIT, Thirawat Sutalungka); see
`Packages/WaoCore/Sources/WaoCore/Resources/THIRD_PARTY_NOTICES`.
