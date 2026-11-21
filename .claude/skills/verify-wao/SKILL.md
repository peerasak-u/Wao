---
name: verify-wao
description: Drive เว่า (Wao, com.peerasak.wao), the offline Thai dictation keyboard for iOS, in an iOS Simulator and capture proof. Use when a change to the container app (mic test, keyboard session, model download, vocabulary) or the WaoKeyboard extension (voice/typing layouts) must be shown working in the real app, not only in `swift test`.
---

# Verify เว่า in the iOS Simulator

เว่า has two surfaces. The container app `com.peerasak.wao` owns the mic and runs the ASR model. The keyboard extension `com.peerasak.wao.keyboard` is UI only and talks to the app through the App Group `group.com.peerasak.wao` (`command.json` from the keyboard, `state.json` from the app). The primary surface for verification is the container app; the keyboard needs a host app's text field and the simulator's keyboard settings.

The simulator has no usable mic. Debug builds read `WAO_FAKE_MIC=<16 kHz mono wav>` and play that file into every utterance at real-time pace. The helper sets it with `launchctl` inside the simulator.

Two tools, never mixed up:

- `scripts/wao-verify` (host side): build, install, seed, doctor, bridge state, evidence dirs, cleanup. Run it from anywhere in the repo as `.claude/skills/verify-wao/scripts/wao-verify <command>`.
- `agent-device` (every UI action and screenshot). Get its path from T3's `device_open` (load `mcp__t3-code__device_list` and `mcp__t3-code__device_open` with ToolSearch first). The path is per session; store it as `AD=<path from device_open>`. Never tap with `simctl`/`idb`.

## Launch

1. Pick a simulator from `device_list` that no other thread has open (the `open` list). Use an existing one: a simulator made with `simctl create` does not appear in T3's device list. Call `device_open` with its `id` and `hostId`; it boots it. Set `U=<udid>` and `AD=<agent-device path>`.
2. Build once per code change (about 25 s warm; the first run downloads ONNX Runtime 1.32.0 from NuGet into the gitignored `Packages/WaoCore/Vendor`):
   ```sh
   S=.claude/skills/verify-wao/scripts/wao-verify
   WAO_VERIFY_UDID=$U $S build          # -> build/verify-dd/Build/Products/Debug-iphonesimulator/Wao.app
   ```
3. Install and seed:
   ```sh
   $S prepare $U                        # model seeded, mic granted, WAO_FAKE_MIC=samples/greeting.wav
   $S prepare $U samples/food.wav       # another clip; samples/*.txt hold each clip's expected words
   $S prepare $U --no-model             # fresh-install state: no model on disk (for the download feature)
   ```
   `prepare` copies the 1 GB int8 model from `$WAO_MODEL_CACHE`, else `.model-cache/int8` in this checkout, else `.model-cache/int8` in the main checkout (worktrees don't have their own). It also turns off `AutomaticMinimizationEnabled` so a software keyboard shows in a headless simulator.
4. Start the app: `$AD open com.peerasak.wao --relaunch`.

Ready means: the snapshot shows button `ลองพูด` and, with the model seeded, text `พร้อมใช้บนเครื่อง` under `โมเดลถอดเสียง`. The model loads lazily on the first mic tap (`กำลังโหลดโมเดล…`, about 1 s), so the first test is slower than later ones.

## Doctor

Run first, and again whenever anything looks off:

```sh
$S doctor $U
```

It is read-only and checks: simulator booted, build present (with its `CFBundleVersion` and git HEAD), app installed and the installed binary equal to `build/verify-dd` (WARN means re-run `prepare`), model files 5/5, App Group container present, and `WAO_FAKE_MIC` pointing at a file that exists. Every reinstall moves the data container to a new UUID; `prepare` re-points `WAO_FAKE_MIC`, but a manual `simctl install` leaves it dangling and the mic test then fails with `wht?` (2003334207). It ends `doctor: OK` or exits 1 with `doctor: NOT READY`.

## Drive

Use snapshot refs or selectors, not coordinates, in the app. Stable handles in the container app:

| Handle | What |
| --- | --- |
| `id=mic-test` | Hero waveform button. Label `ลองพูด` when ready, `หยุดและถอดเสียง` while recording |
| `id=result-text` | Mic-test transcription text |
| `id=session-toggle` | Keyboard session pill (`เปิด` / `ปิด`) |
| `id=vocabulary-card` | Opens คลังคำศัพท์ |
| `id=credits-footer` | Opens เครดิต |
| `id=import-summary` | Import preview line in นำเข้าหลายคำ |

Keyboard extension keys do not appear in agent-device's accessibility tree; tap them by point coordinates from a screenshot (`agent-device screenshot` saves 1x points, which is what `press x y` takes).

The feature map in [`features/README.md`](features/README.md) is the recipe source. Read its index, pick the feature file, and follow its `Driving it` bullets. A proof that drives one entry point is incomplete when the map lists others.

Run state of the bridge at any point (what the keyboard would see):

```sh
$S state $U     # state.json: {"off":{}} | {"idle":{...}} | {"listening":{"heard":...}} | {"done":...}; command.json
```

## Evidence

```sh
E=$($S evidence <feature-id>)   # build/verify-evidence/<yyyymmdd-hhmmss>-<feature-id>/, survives cleanup
$AD snapshot -i > $E/01-before.ax.txt
$AD screenshot $E/01-before.png
$S state $U > $E/01-before.bridge.txt
```

Proof standards:

- Drive the real user path: tap the buttons a user taps. Don't call internal setters, write `command.json` yourself, or edit `vocabulary.json` to fake a result.
- Capture the action and the resulting state: a numbered before / during / after triple of accessibility snapshot, screenshot and bridge state.
- Verify side effects alongside the screen: `state.json` in the App Group for sessions and dictation, `Library/Application Support/vocabulary.json` in the data container (`xcrun simctl get_app_container $U com.peerasak.wao data`) for vocabulary, the model directory for downloads.
- The fake mic is the one allowed mock: it replaces only the hardware boundary (`AudioCapture`), and everything after it (featurizer, model, beam search, clean-up, bridge) is real. Say in the report which wav was used and compare against its `samples/<name>.txt`. Expect the words, not the spacing: the model drops the space in `สวัสดีครับ วันนี้อากาศดีมาก`.
- A simulator proof does not cover real-mic capture, background audio keep-alive on a device, or memory limits of the extension on hardware. Say so when the change touches them.

## Cleanup

```sh
$S cleanup $U       # unsets WAO_FAKE_MIC, terminates the app, uninstalls it only if prepare installed it
```

Then `device_close` the simulator you opened (`shutdown: true` only if you booted it). Never `killall Simulator` or kill by process name. Cleanup leaves `build/verify-evidence/` and `build/verify-dd/` alone; report evidence paths from there. If you changed keyboard settings (added เว่า, Full Access), they stay with that simulator; mention it in the report.

## Isolation

One simulator runs one copy of `com.peerasak.wao` with one App Group, so two runs on the same simulator corrupt each other's `state.json`. Run in parallel only on different simulators. If doctor shows the app was already installed before your `prepare` (cleanup then prints `kept com.peerasak.wao`), someone else may be using that simulator: stop and pick another.

## Helpers

`scripts/wao-verify` (executable). `wao-verify` with no args prints usage:

```
build | prepare <udid> [wav] [--no-model] | fake-mic <udid> <wav> | doctor <udid> | state <udid> | evidence <name> | cleanup <udid>
```

`fake-mic` swaps the clip without reinstalling; relaunch the app after it (`$AD open com.peerasak.wao --relaunch`), since the env var is read at capture start of a new process.
