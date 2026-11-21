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
