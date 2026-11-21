# Model download

On first launch the app has no model. Setup step 1 downloads the 1 GB int8 OpenThai2.0 ASR files from Hugging Face in a background URLSession, with pause, resume across launches and retry, and then shows `พร้อมใช้บนเครื่อง`.

## Sub-features

- `download-start` taps `ดาวน์โหลด`; a progress bar appears.
- `download-pause` taps `หยุด`; the button becomes `ดาวน์โหลดต่อ`.
- `download-resume` taps `ดาวน์โหลดต่อ`; progress continues from where it was, also after relaunch.
- `download-retry` taps `ลองอีกครั้ง` after a failure.
- `download-ready` shows a done mark on step 1 and enables the mic test and session.

## How to get to it (user POV)

- Open เว่า for the first time; the `ตั้งค่า` card's step 1 `โมเดลถอดเสียง` shows `ดาวน์โหลด` and `แนะนำให้ต่อ Wi-Fi · ดาวน์โหลดครั้งเดียว`.
- From the hero panel's `ไปที่ขั้นที่ 1` when the model is missing.

## Driving it with agent-device

Preconditions:

- `$S prepare $U --no-model` (removes the model directory), app relaunched.
- Network access to huggingface.co. The full download is about 1 GB.

- **Missing.** Capture `01-missing.*`: step 1 shows `ดาวน์โหลด`; the hero shows `ไปที่ขั้นที่ 1`.
- **Start.** Run `$AD press 'label=ดาวน์โหลด' --settle`. The button becomes `หยุด` and a progress bar appears.
- **Pause.** After about 10 s run `$AD press 'label=หยุด' --settle`. The button becomes `ดาวน์โหลดต่อ` and the bar keeps its position. The model directory (`<data>/Library/Application Support/Models/openthai2.0-asr-streaming-int8/`) holds a `.part` or resume data.
- **Resume after relaunch.** Run `$AD open com.peerasak.wao --relaunch`, then `$AD press 'label=ดาวน์โหลดต่อ'`. The bar starts from the paused position, not zero.
- **Ready.** Wait for the text `พร้อมใช้บนเครื่อง` (`$AD wait text "พร้อมใช้บนเครื่อง" 1800000`). The directory holds `encoder.int8.onnx.data`, `openthai2.0-asr-streaming-int8.asr.zip` and the extracted `encoder.int8.onnx`, `decoder_joint.onnx`, `tokens.txt`. Run the mic test as the end-to-end proof that the files load.
- **Proof.** Screenshots at missing, downloading, paused, resumed and ready, plus `ls -l` of the model directory at paused and ready.

## Gotchas

- Hugging Face redirects to a signed CDN URL valid about 1 hour; resume data older than that is salvaged into `.part` and continued with a Range request. A pause/resume proof within the hour does not cover that path.
- `prepare` without `--no-model` seeds the model, so the download UI never appears; use `--no-model` for this feature only.
- On the simulator, a running background task's temp file lives outside the app container; only a paused one is visible in `tmp/`.
- The download is the slowest proof here. Skip the full download when only pause/resume changed, and say so.
