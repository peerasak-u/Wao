# Typing layouts

The เว่า keyboard types without the mic: Thai Kedmanee, a symbols page and an emoji panel. It has no English letters: English words come from dictation, or from the system's English keyboard through the globe. The keyboard always opens here. Without Full Access this is the whole keyboard, with a banner explaining how to enable voice; with Full Access a `Dictation` key starts dictation in one tap (App Review 4.4.1 requires typing to work without Full Access).

## Sub-features

- `typing-kedmanee` types Thai; vowel and tone mark keys draw on a faint อ.
- `typing-symbols` switches page with `123` and back with `กขค`.
- `typing-emoji` opens the emoji panel with the emoji key (a smiling face, where iOS has its own). Category icons along the bottom jump to their section and light up for the one in view; a tap types an emoji; a long press on one with skin tones shows them; `Frequently Used` leads the grid the next time it opens; `กขค` returns to the Thai letters and delete deletes.
- `typing-shift` shows the shifted Thai row, or the second symbols page on `123`.
- `typing-banner` (no Full Access) shows `เปิดการเข้าถึงแบบเต็มเพื่อพิมพ์ด้วยเสียง`; tapping it explains the steps, `แตะเพื่อกลับไปพิมพ์` closes it.
- `typing-dictation-key` (Full Access) shows a `Dictation` key left of space; one tap starts dictation (see `keyboard-dictation.md`).
- `typing-pending` shows a small spinner and `กำลังถอดเสียง` in the strip while text confirmed with ✓ is on its way; with suggestions showing, only the spinner, beside them. Typing works meanwhile.
- `typing-decode` types the key the context makes likely when a Thai tap lands near a key border; a tap in the middle of a key always types that key.
- `typing-suggestions` shows up to three word completions in the strip above the keys; tapping one inserts the rest of the word.

## How to get to it (user POV)

- Without Full Access: switch to เว่า in any text field; it opens on Kedmanee.
- With Full Access: switch to เว่า; it also opens on Kedmanee, with a mic key left of space.

## Driving it with agent-device

Preconditions:

- เว่า added as a keyboard (see `keyboard-dictation.md`), Full Access off for the no-Full-Access path.
- A host app text field open, software keyboard visible.

- **Open.** Focus the field. Capture `$AD screenshot $E/01-kedmanee.png`; the banner and the Kedmanee rows show.
- **Type Thai.** Tap the keys for ส ว ั ส ด ี by coordinates. The host field (from `$AD snapshot -i`) contains `สวัสดี`.
- **Symbols.** Tap `123`, type `1`; tap `กขค` to return.
- **Emoji.** On an iPhone 17 Pro Max (iOS 26.4) in Safari's address bar: emoji key (85, 861); bar icons at y = 856, กขค x = 32, clock 78, then every 35.4 pt to flags 362, delete 406; glyph centres at y = 651.8 + 40·row, x = 23.5 + 42·column. Tap a category, two emoji, then delete, reading the field from `$AD snapshot -i` after each. Long-press an emoji with skin tones (people, past four pans of Smileys & People) and tap a tone. Tap `กขค`, tap the emoji key again: `Frequently Used` shows them, newest first. The emoji cells are in the accessibility tree as keys named after Unicode (`man cook: dark skin tone`), unlike the letter keys. `scripts/emoji-memwalk $AD $U` restarts the keyboard, walks every category and prints the extension's footprint.
- **Emoji parity.** On the same host and simulator, capture Apple's emoji keyboard and เว่า's, each on Smileys & People, at `--pixel-density 3`, and run `uv run tools/emoji_metrics.py APPLE.png WAO.png`. Panel top, glyph row and column centres and the header ink must agree within 1 pt; Apple's 40 pt search band shows only in Apple's. The panel is taller than the typing page (313 pt at 390, 324 at 440), so the host moves up when it opens, as it does for Apple's.
- **Banner.** Tap the banner, capture the explanation, tap `แตะเพื่อกลับไปพิมพ์`.
- **Full Access path.** Turn Full Access on, reopen the keyboard: it opens on Kedmanee with a `Dictation` key left of space. One tap shows the dictation view (✕, waveform, ✓); ✕ returns to typing.
- **Proof.** Screenshot per layout plus the host field's final value in a snapshot.
- **Decode.** On an iPhone 16e (390 pt wide, iOS 26.1) the first row of caps starts at y = 559 and rows repeat every 43.2 pt. Key centres are x = 21.4 + 31.56·column (shift takes column 0 of the bottom letter row), y = 577.7 + 43.2·row. Type `แล้` with centre taps (แ (116.3, 707.3), ล (368.6, 620.9), ้ (179.2, 664.1)), then tap (287.5, 664.1), which sits on ส 2.5 pt from the ว border: the field must end `แล้ว`. Then type `แล้ส` with centre taps: the field must end `แล้ส`, because a tap in the middle of a key is never second-guessed. `.build/release/wao-typing-eval` prints more border taps.
- **Apple parity.** In the same host field, switch to Apple's ภาษาไทย keyboard and capture its pages at `--pixel-density 3` as thai-letters, thai-shifted and thai-numbers in `$E/apple/`. Switch to เว่า on its Thai letters page and run `scripts/capture-typing-pages $AD $E/wao`, then `uv run tools/keyboard_parity.py $E/apple $E/wao --out $E/overlays`. Every cap must be within 1 pt; the table also prints each label's offset, which is reported, not gated.
- **Suggestions.** Type `สวัส`: the strip shows สวัสดี in the middle. Tap it: the field ends `สวัสดี`.

## Gotchas

- iOS gives a touch on a fully transparent part of a third-party keyboard to the app behind it. If key taps reach nothing while shift and `123` still work, look for a transparent view that should catch touches.
- The key layouts come from WaoCore's `Typing`; `swift test` covers their logic, not the touch targets, so the simulator run is what proves hit areas.
- Our own globe key only shows where iOS does not draw one (home-button devices). No iPhone 17-family simulator shows it.
- Typing does not need the app, a session or the model.
- iOS 26 gives the extension a view 9 pt narrower than a 390 pt screen, centred, so `KeyLayout` takes the screen width too and draws the caps where the system keyboard has them.
- On iOS 26.1 (the 16e) the system keyboard sits 2 pt lower than an extension can reach, so the parity tool fails there on dy = −2.0 for every cap; the "panel top difference taken out" line is the one to read. On iOS 26.4 it passes outright.
- The globe menu's items move with the keyboard that is showing, and its bottom row switches to one-handed mode. Screenshot the menu before tapping an item.
- CoreText keeps the image of every emoji it draws for the life of the process, so the panel draws them at 2x (16 KB each instead of 48 KB at 3x). A walk through every category is the worst case; compare its footprint with the typing page's.
- After switching to เว่า from an Apple keyboard that shows predictions, iOS draws 17 pt of empty keyboard background above the extension until the host app relaunches. Every page sits 17 pt higher; the extension's own window does not include it, so it cannot see or undo it. Relaunch the host before measuring.
- Reinstalling the app falls back to Apple's keyboard; switch back to เว่า before capturing, or the parity tool compares Apple with Apple (it refuses identical files).
