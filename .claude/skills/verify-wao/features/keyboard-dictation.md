# Keyboard dictation

With Full Access, the เว่า keyboard opens on typing and its `Dictation` key (mic, next to space) leads to a large mic. With a live session in the app, the user taps the mic, speaks while the words show live, then taps ✓ to insert the text into whatever field they are typing in, or ✕ to discard.

## Sub-features

- `dictation-start` taps the mic; the keyboard shows a waveform and live words.
- `dictation-insert` taps `Done` (✓); the transcription is inserted into the host field.
- `dictation-cancel` taps `Cancel` (✕); nothing is inserted.
- `dictation-no-session` taps the mic with no live session; the keyboard opens the app and shows `เปิดแอปเว่าเพื่อเริ่มเซสชัน แล้วกลับมาที่นี่แตะไมค์อีกครั้ง`.
- `dictation-empty` shows `ไม่ได้ยินเสียงพูด ลองอีกครั้ง` for silence.
- `dictation-voice-keys` uses space (`เว้นวรรค`), delete and return on the voice layout, and `Keyboard` to switch to typing.

## How to get to it (user POV)

- Settings › General › Keyboard › Keyboards › Add New Keyboard… › เว่า, then เว่า › Allow Full Access.
- Open เว่า and turn on the keyboard session.
- In any app with a text field, switch to เว่า with the globe, tap the `Dictation` key, then tap the mic.

## Driving it with agent-device

Preconditions:

- Baseline from `README.md`. `$S prepare` already turned off `AutomaticMinimizationEnabled` so the software keyboard shows.
- เว่า added as a keyboard with Full Access on this simulator. Do it once through Settings with `$AD open com.apple.Preferences` and labels from `$AD snapshot -i`; accept the Full Access alert with `$AD alert accept`.
- Session on: in เว่า, `$AD press 'id=session-toggle'`; `$S state $U` shows `idle`.

- **Host field.** Open a host app with a plain text field, for example `$AD open com.apple.mobilesafari` and tap the address bar. The keyboard opens on Kedmanee. Tap the `Dictation` key (mic, left of space) by coordinates, take `$AD screenshot $E/01-keyboard.png` and confirm the เว่า mic layout (big mic, `แตะเพื่อพูด`). If another keyboard shows, long-press the globe and pick เว่า.
- **Start.** Tap the mic at its point coordinates from the screenshot (`$AD press <x> <y>`). `$S state $U` moves to `listening` with the start command's id; `command.json` holds a `start` with the same id.
- **Live words.** After 4 s capture `02-listening.png`; the keyboard shows the words heard so far.
- **Insert.** Tap ✓ (`Done`) by coordinates. `state.json` passes through `transcribing` to `done` with that id. The host field contains `สวัสดีครับวันนี้อากาศดีมาก` (`$AD snapshot -i` of the host shows the field value).
- **Cancel.** Repeat Start, then tap ✕ (`Cancel`). The field is unchanged and `state.json` goes back to `idle`.
- **No session.** Turn the session off in the app, return to the host, tap the mic. The app opens and the session starts.
- **Proof.** Before/during/after screenshots of the host app with the keyboard, plus `.bridge.txt` at each step, plus the host field's value from a snapshot.

## Gotchas

- Not yet driven by this skill: the keyboard steps above are built from the code and project notes, not a recorded run. The first run that drives them should correct the coordinates and host app here.
- Keyboard keys are not in the accessibility tree; coordinates come from a fresh screenshot because the keyboard's height is fixed at 270 pt but its y offset depends on the host app.
- After reinstalling, the globe may skip เว่า; long-press the globe and pick it. A first install can leave it off under Settings › Apps › เว่า › Keyboards.
- The keyboard waits 1.5 s for the app to answer a start; with a slow first model load it gives up and opens the app instead. Run the mic test once first to load the model.
- In headless T3 simulators no keyboard appears until `AutomaticMinimizationEnabled` is false and the host app is relaunched.
- A `done` from an earlier utterance is ignored; match ids between `command.json` and `state.json`.
