# เว่า

Offline Thai dictation keyboard for iOS. The keyboard extension is UI only; the app holds the mic and runs
iapp/OpenThai2.0-ASR-Streaming-ONNX (int8) on the CPU with ONNX Runtime.

Try the beta on [TestFlight](https://testflight.apple.com/join/jU4rVm8a). Report bugs and ideas in
[GitHub Issues](https://github.com/peerasak-u/thai-wow-keyboard/issues/new/choose), in Thai or English.

## Credits

- **Speech recognition model:** [OpenThai2.0-ASR-Streaming](https://huggingface.co/iapp/OpenThai2.0-ASR-Streaming)
  by **iApp Technology**, launched with **AIEAT** and released free under
  [OpenMDW-1.1](https://openmdw.ai/license/1-1/). It is part of OpenThai (formerly OpenThaiGPT) and built on NVIDIA's
  Nemotron ASR streaming model. The app downloads the int8 files of its ONNX export,
  [iapp/OpenThai2.0-ASR-Streaming-ONNX](https://huggingface.co/iapp/OpenThai2.0-ASR-Streaming-ONNX), at setup.
  Thank you to iApp and AIEAT for opening it up.
- **[ONNX Runtime](https://www.nuget.org/packages/Microsoft.ML.OnnxRuntime/1.32.0) 1.32.0** (Microsoft, MIT) runs
  the model and ships inside the app.
- **[PoodPim](https://github.com/thirawat/PoodPim)** (MIT, Thirawat Sutalungka): the beam search with hotword
  biasing, the text clean-up and the default vocabulary and corrections lists are adapted from it.

- **Typing data** (CC0): Common Voice Thai sentences, wisesight-sentiment and PyThaiNLP's word list and Thai
  National Corpus frequencies. The keyboard's language model and word suggestions are built from them.

The app shows all of this, with each licence in full, under เครดิตและสัญญาอนุญาต at the foot of its main screen.
The texts live in `Packages/WaoCore/Sources/WaoInference/Resources` (the model's notice of origin with OpenMDW-1.1,
and ONNX Runtime's LICENSE and ThirdPartyNotices, which `tools/fetch_onnxruntime.sh` copies from the NuGet package)
and `Packages/WaoCore/Sources/WaoCore/Resources/THIRD_PARTY_NOTICES` (PoodPim).

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

## Typing model

The Thai letters page types the key a touch most likely meant, from where the finger landed, how fast the typing is
and what came before, and the strip above the keys offers completions of the word being typed. Both read
`Packages/WaoCore/Sources/WaoCore/Resources/thai-typing.bin`, a pruned character 6-gram and word list memory-mapped
by `TypingModel`. Every tunable lives in `TapTuning.shipped`.

```sh
uv run tools/build_typing_model.py   # downloads the pinned corpora into .model-cache/typing-corpora, writes the .bin
```

The build also rewrites the test fixtures it derives: the held-out lines it never trained on and golden
probabilities the Swift reader must reproduce. The same sources and options give the same bytes.

```sh
cd Packages/WaoCore && swift build -c release --product wao-typing-eval
.build/release/wao-typing-eval            # JSON lines: fixed-noise table, speed buckets, latency, border taps to try
.build/release/wao-typing-eval sweep      # the speed mix over a grid of tunings, best first
```

`wao-typing-eval` replays the held-out lines as noisy taps on a 390 x 242 pt key grid through the shipped
`KeyLayout`, `TypingModel` and `TapDecoder`, and counts what the geometric keyboard and each decoder typed.

## License

The code is [MIT](LICENSE). The model, the ONNX Runtime binaries and the typing data keep their own licences,
listed under Credits.
