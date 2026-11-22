# Keyboard dictation

With Full Access, the เว่า keyboard opens on typing and its `Dictation` key (mic, left of space) starts dictation in one tap. With a live session in the app, the user taps the mic and speaks while the words show live. ✓ returns to typing at once, and the text lands at the cursor when the app finishes transcribing. ✕ discards it and returns to typing.

## Sub-features

- `dictation-start` taps the mic key once; the keyboard shows `กำลังฟัง...`, a waveform and live words.
- `dictation-insert` taps `Done` (✓); the keyboard is back on typing straight away, with a spinner and `กำลังถอดเสียง` in the strip until the transcription is inserted into the host field.
- `dictation-cancel` taps `Cancel` (✕); typing comes back and nothing is inserted.
- `dictation-queued` taps the mic while a confirmed transcription is still pending; the dictation view shows `กำลังเริ่ม...`, the pending text is inserted first, then the new start goes to the app.
- `dictation-no-session` taps the mic with no live session; the keyboard stays on typing with `เปิดแอปเว่าเพื่อเริ่มเซสชัน แล้วกลับมาที่นี่แตะไมค์อีกครั้ง` and opens the app, which starts the session.
- `dictation-empty` shows `ไม่ได้ยินเสียงพูด ลองอีกครั้ง` for silence; a failed transcription shows the app's reason.

## How to get to it (user POV)

- Settings › General › Keyboard › Keyboards › Add New Keyboard… › เว่า, then เว่า › Allow Full Access.
- Open เว่า and turn on the keyboard session.
- In any app with a text field, switch to เว่า with the globe and tap the `Dictation` key.

## Driving it with agent-device

Preconditions:

- Baseline from `README.md`. `$S prepare` already turned off `AutomaticMinimizationEnabled` so the software keyboard shows.
- เว่า added as a keyboard with Full Access on this simulator. Do it once through Settings with `$AD open com.apple.Preferences` and labels from `$AD snapshot -i` (General › Keyboard › Keyboards › Keyboards › เว่า). The `Allow Full Access` switch may not take a ref press; press its point coordinates, then press `Allow` in the alert by ref.
- Run the mic test once in the app so the model is loaded.
- Session on: in เว่า, `$AD press 'id=session-toggle'`; `$S state $U` shows `idle`.

On an iPhone 17 (iOS 26.4) in Safari's address bar, the keys are at these points: mic key (128, 780), ✕ (43, 760), ✓ (358, 760). Check them against a fresh screenshot.

- **Host field.** `$AD open com.apple.mobilesafari --relaunch`, then press the address bar (at the bottom of the start page, about (201, 816) on an iPhone 17). The keyboard opens on Kedmanee with the mic key left of space. If another keyboard shows, long-press the globe and pick เว่า.
- **Start.** Press the mic key once. Within 0.3 s the keyboard shows `กำลังฟัง...` and the waveform; `$S state $U` is `listening` with the start command's id.
- **Live words.** After 2.5 s capture `01-listening.png`; the keyboard shows `สวัสดีครับวันนี้อากาศดีมาก`.
- **Insert.** Press ✓ and capture straight away: typing is back with the spinner and `กำลังถอดเสียง`, and `state.json` is `transcribing`. Within 3 s it is `done` with that id, and `$AD snapshot` shows the address field's value `สวัสดีครับวันนี้อากาศดีมาก`.
- **Cancel.** Start again, then press ✕. Typing is back, the field is unchanged, and `state.json` goes to `idle`.
- **Queued.** Start, press ✓, then the mic key at once. The first text is inserted and the second utterance reaches `listening`; ✓ inserts it too.
- **No session.** Turn the session off in the app, return to the host, press the mic key. The notice shows on typing only for about 0.1 s before the app comes forward, so a screenshot misses it: record with `$AD record start --scope device $E/no-session.mp4`, press, `$AD record stop`, and pull the frame with `ffmpeg -ss <t> -i ... -frames:v 1`. The app opens and `state.json` goes `off` to `idle`.
- **Proof.** Before/during/after screenshots of the host app with the keyboard, plus `.bridge.txt` at each step, plus the host field's value from a snapshot.

## Gotchas

- Keyboard keys are not in the accessibility tree; coordinates come from a fresh screenshot because the keyboard's height is fixed but its y offset depends on the host app.
- The app must keep running in the background to hear the keyboard. A real mic does that; the fake mic runs a silent output engine for the same reason. Without it the app is suspended, the keyboard's 1.5 s start timeout fires and opens the app.
- After reinstalling, the globe may skip เว่า; long-press the globe and pick it. A first install can leave it off under Settings › Apps › เว่า › Keyboards.
- On return from the app iOS builds a new keyboard controller, so a notice shown before the app opened is gone.
- `agent-device snapshot` and `press` bring the session's app to the front; after `open com.peerasak.wao`, open the host app again before pressing keys.
- In headless T3 simulators no keyboard appears until `AutomaticMinimizationEnabled` is false and the host app is relaunched.
- A `done` from an earlier utterance is ignored; match ids between `command.json` and `state.json`.
