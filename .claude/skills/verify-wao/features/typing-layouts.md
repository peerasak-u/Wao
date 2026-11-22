# Typing layouts

The เว่า keyboard types without the mic: Thai Kedmanee, English QWERTY and a symbols page. Without Full Access this is the whole keyboard, with a banner explaining how to enable voice; with Full Access it is a detour from the mic layout (App Review 4.4.1 requires typing to work without Full Access).

## Sub-features

- `typing-kedmanee` types Thai; vowel and tone mark keys draw on a faint อ.
- `typing-qwerty` switches language with the language key and types English.
- `typing-symbols` switches page with `123` and back with `กขค` / `ABC`.
- `typing-shift` shows the shifted Thai or upper-case row.
- `typing-banner` (no Full Access) shows `เปิดการเข้าถึงแบบเต็มเพื่อพิมพ์ด้วยเสียง`; tapping it explains the steps, `แตะเพื่อกลับไปพิมพ์` closes it.
- `typing-to-voice` (Full Access) shows a `Dictation` key that returns to the mic layout.
- `typing-decode` types the key the context makes likely when a Thai tap lands near a key border; a tap in the middle of a key always types that key.
- `typing-suggestions` shows up to three word completions in the strip above the keys; tapping one inserts the rest of the word.

## How to get to it (user POV)

- Without Full Access: switch to เว่า in any text field; it opens on Kedmanee.
- With Full Access: switch to เว่า, tap the `Keyboard` key next to space.

## Driving it with agent-device

Preconditions:

- เว่า added as a keyboard (see `keyboard-dictation.md`), Full Access off for the no-Full-Access path.
- A host app text field open, software keyboard visible.

- **Open.** Focus the field. Capture `$AD screenshot $E/01-kedmanee.png`; the banner and the Kedmanee rows show.
- **Type Thai.** Tap the keys for ส ว ั ส ด ี by coordinates. The host field (from `$AD snapshot -i`) contains `สวัสดี`.
- **QWERTY.** Tap the language key, type `hi`. The field ends with `hi`.
- **Symbols.** Tap `123`, type `1`; tap `ABC` to return.
- **Banner.** Tap the banner, capture the explanation, tap `แตะเพื่อกลับไปพิมพ์`.
- **Full Access path.** Turn Full Access on, reopen the keyboard: it opens on the mic; tap `Keyboard`, then the `Dictation` key to return.
- **Proof.** Screenshot per layout plus the host field's final value in a snapshot.
- **Decode.** On an iPhone 16e (390 pt wide) the key grid starts at y = 527 and a row is 48.4 pt tall. Key centres are x = 16.25 + 32.5·column (the bottom letter row starts one key further right), y = 527 + 24.2 + 48.4·row. Type `แล้` with centre taps, then tap (290, 527 + 130.9), which sits on ส 2.5 pt from the ว border: the field must end `แล้ว`. Then type `แล้ส` with centre taps: the field must end `แล้ส`, because a tap in the middle of a key is never second-guessed. `.build/release/wao-typing-eval` prints more border taps.
- **Suggestions.** Type `สวัส`: the strip shows สวัสดี in the middle. Tap it: the field ends `สวัสดี`.

## Gotchas

- iOS gives a touch on a fully transparent part of a third-party keyboard to the app behind it. If key taps reach nothing while shift and `123` still work, look for a transparent view that should catch touches.
- The key layouts come from WaoCore's `Typing`; `swift test` covers their logic, not the touch targets, so the simulator run is what proves hit areas.
- Our own globe key only shows where iOS does not draw one (home-button devices). No iPhone 17-family simulator shows it.
- Typing does not need the app, a session or the model.
