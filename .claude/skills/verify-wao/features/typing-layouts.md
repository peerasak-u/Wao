# Typing layouts

The เว่า keyboard types without the mic: Thai Kedmanee, English QWERTY and a symbols page. The keyboard always opens here. Without Full Access this is the whole keyboard, with a banner explaining how to enable voice; with Full Access a `Dictation` key leads to the mic layout (App Review 4.4.1 requires typing to work without Full Access).

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
- With Full Access: switch to เว่า; it also opens on Kedmanee. From the mic layout, the `Keyboard` key next to space comes back.

## Driving it with agent-device

Preconditions:

- เว่า added as a keyboard (see `keyboard-dictation.md`), Full Access off for the no-Full-Access path.
- A host app text field open, software keyboard visible.

- **Open.** Focus the field. Capture `$AD screenshot $E/01-kedmanee.png`; the banner and the Kedmanee rows show.
- **Type Thai.** Tap the keys for ส ว ั ส ด ี by coordinates. The host field (from `$AD snapshot -i`) contains `สวัสดี`.
- **QWERTY.** Tap the language key, type `hi`. The field ends with `hi`.
- **Symbols.** Tap `123`, type `1`; tap `ABC` to return.
- **Banner.** Tap the banner, capture the explanation, tap `แตะเพื่อกลับไปพิมพ์`.
- **Full Access path.** Turn Full Access on, reopen the keyboard: it opens on Kedmanee with a `Dictation` key left of space; tap it for the mic layout, then `Keyboard` to return.
- **Proof.** Screenshot per layout plus the host field's final value in a snapshot.
- **Decode.** On an iPhone 16e (390 pt wide, iOS 26.1) the first row of caps starts at y = 559 and rows repeat every 43.2 pt. Key centres are x = 21.4 + 31.56·column (shift takes column 0 of the bottom letter row), y = 577.7 + 43.2·row. Type `แล้` with centre taps (แ (116.3, 707.3), ล (368.6, 620.9), ้ (179.2, 664.1)), then tap (287.5, 664.1), which sits on ส 2.5 pt from the ว border: the field must end `แล้ว`. Then type `แล้ส` with centre taps: the field must end `แล้ส`, because a tap in the middle of a key is never second-guessed. `.build/release/wao-typing-eval` prints more border taps.
- **Apple parity.** In the same host field, switch to Apple's ภาษาไทย keyboard and capture its pages at `--pixel-density 3` as thai-letters, thai-shifted, thai-numbers, english-letters, english-shifted and english-numbers in `$E/apple/`. Switch to เว่า on its Thai letters page and run `scripts/capture-typing-pages $AD $E/wao`, then `uv run tools/keyboard_parity.py $E/apple $E/wao --out $E/overlays`. Every cap must be within 1 pt; the table also prints each label's offset, which is reported, not gated.
- **Suggestions.** Type `สวัส`: the strip shows สวัสดี in the middle. Tap it: the field ends `สวัสดี`.

## Gotchas

- iOS gives a touch on a fully transparent part of a third-party keyboard to the app behind it. If key taps reach nothing while shift and `123` still work, look for a transparent view that should catch touches.
- The key layouts come from WaoCore's `Typing`; `swift test` covers their logic, not the touch targets, so the simulator run is what proves hit areas.
- Our own globe key only shows where iOS does not draw one (home-button devices). No iPhone 17-family simulator shows it.
- Typing does not need the app, a session or the model.
- iOS 26 gives the extension a view 9 pt narrower than a 390 pt screen, centred, so `KeyLayout` takes the screen width too and draws the caps where the system keyboard has them.
- On iOS 26.1 (the 16e) the system keyboard sits 2 pt lower than an extension can reach, so the parity tool fails there on dy = −2.0 for every cap; the "panel top difference taken out" line is the one to read. On iOS 26.4 it passes outright.
- The globe menu's items move with the keyboard that is showing, and its bottom row switches to one-handed mode. Screenshot the menu before tapping an item.
- Reinstalling the app falls back to Apple's keyboard; switch back to เว่า before capturing, or the parity tool compares Apple with Apple (it refuses identical files).
