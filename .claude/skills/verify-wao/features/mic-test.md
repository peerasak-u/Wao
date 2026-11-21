# Mic test

The hero waveform on the app's main screen is a try-it button: the user taps it, speaks, taps again, and reads what the model heard with its timing and a copy button. If the keyboard session was off, the test opens the mic itself and closes it again when done.

## Sub-features

- `mic-test-record` starts listening and shows live words (`กำลังฟัง · แตะเพื่อหยุด` with a timer).
- `mic-test-result` stops, transcribes and shows the text in `result-text` plus `<n> วินาที · ถอดใน <n> วินาที`.
- `mic-test-copy` copies the result (`คัดลอก` becomes `คัดลอกแล้ว`).
- `mic-test-again` runs again from the result (`แตะเพื่อลองอีกครั้ง`).
- `mic-test-blocked` shows the blocking setup step (`ไปที่ขั้นที่ <n>`) when the model or mic permission is missing.
- `mic-test-session-restore` leaves the keyboard session as it found it: off stays off, on returns to idle.

## How to get to it (user POV)

- Open เว่า and tap the waveform under the tagline (label `ลองพูด`).

## Driving it with agent-device

Preconditions:

- Baseline from `README.md` (model seeded, mic granted, `WAO_FAKE_MIC` = `samples/greeting.wav`), app opened with `$AD open com.peerasak.wao --relaunch`.
- Keyboard session off: `$S state $U` prints `state.json: {"off":{}}`.

- **Evidence dir.** Run `E=$($S evidence mic-test)`, then `$AD snapshot -i > $E/01-before.ax.txt`, `$AD screenshot $E/01-before.png`, `$S state $U > $E/01-before.bridge.txt`. The snapshot has button `ลองพูด` and text `แตะเพื่อลองพูด`.
- **Start.** Tap the waveform. Run `$AD press 'id=mic-test' --settle`. The diff shows the button `[disabled]` with `กำลังโหลดโมเดล…` (first run only), then `กำลังฟัง · แตะเพื่อหยุด`.
- **Listen.** Let the clip play. Run `$AD wait 4000`, then capture `02-listening.*` the same way. `02-listening.bridge.txt` holds `{"listening":{"heard":{"text":"สวัสดีครับวันนี้อากาศดีมาก",...},"language":"th-mix"}}`.
- **Stop.** Tap the waveform again. Run `$AD press 'id=mic-test'` and `$AD wait 'id=result-text' 60000`.
- **Result.** Capture `03-result.*`. `03-result.ax.txt` contains text `สวัสดีครับวันนี้อากาศดีมาก` and a line matching `วินาที · ถอดใน`. `03-result.bridge.txt` is back to `{"off":{}}` because the test opened the session and closed it.
- **Session restore (on).** Tap `id=session-toggle` (`เปิด`), run the test again, and check `$S state $U` shows `idle` afterwards, not `off`.
- **Blocked.** Run `$S prepare $U --no-model`, relaunch, and confirm the panel shows `ไปที่ขั้นที่ 1` instead of starting. Restore with `$S prepare $U`.

## Gotchas

- The first tap after launch loads the model (about 1 s on the simulator); `press --settle` returns during `กำลังโหลดโมเดล…`. Wait for the listening text or `result-text`, never a fixed short sleep.
- The fake mic plays the wav from the start of each utterance, then silence. Stopping before the clip ends truncates the words; greeting.wav is 3.1 s, so wait at least 4 s.
- The model writes Thai without the spaces in `samples/*.txt`. Compare words, not the exact string.
- `WAO_FAKE_MIC` is read at app launch; after `$S fake-mic` relaunch the app.
- An empty result shows `(ไม่ได้ยินเสียงพูด)`. With a fake mic that means `WAO_FAKE_MIC` is unset or dangling: run `$S doctor $U`.
