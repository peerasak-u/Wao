# Vocabulary

คลังคำศัพท์ lists English words the user wants written in Latin letters (company names, products, jargon), in groups that can be switched on and off. The words bias the model's beam search and clean-up, so dictation spells them in English.

## Sub-features

- `vocab-summary` shows `<n> คำ · เปิด <a> จาก <b> กลุ่ม` on the main screen card.
- `vocab-group-toggle` switches a group on or off; the count of effective words changes.
- `vocab-add-word` adds a word in a group (`เพิ่มคำ (คั่นหลายคำด้วย ,)` and the ⊕ button).
- `vocab-import` pastes many words (`นำเข้าหลายคำ`); the preview reads `เพิ่ม <n> คำ · ซ้ำ <n> คำ`.
- `vocab-new-group` creates a group (`กลุ่มใหม่`), renames (`เปลี่ยนชื่อ`) and deletes (`ลบกลุ่ม`) it.
- `vocab-reset` restores the bundled list (`คืนค่าเริ่มต้น`).
- `vocab-effect` makes a dictated English term come out in Latin letters.

## How to get to it (user POV)

- Open เว่า and tap the `คลังคำศัพท์` card below the setup card.

## Driving it with agent-device

Preconditions:

- Baseline from `README.md`, app relaunched, vocabulary at the bundled default (fresh `prepare` install, or `คืนค่าเริ่มต้น`).

- **Open.** Run `$AD scroll down` until `id=vocabulary-card` is visible, then `$AD press 'id=vocabulary-card' --settle`. The screen title is `คลังคำศัพท์` with the big count and `คำที่ใช้อยู่`.
- **New group and word.** Tap `กลุ่มใหม่`, fill `ชื่อกลุ่มใหม่` with `Verify`, confirm, open the group, fill `เพิ่มคำ (คั่นหลายคำด้วย ,)` with `Supabase, Vercel` and tap ⊕. The group shows `2 คำ`.
- **Import.** Tap `นำเข้าหลายคำ`, paste `Figma, Supabase`. `id=import-summary` reads `เพิ่ม 1 คำ · ซ้ำ 1 คำ`.
- **Persisted.** After 1 s, read `$(xcrun simctl get_app_container $U com.peerasak.wao data)/Library/Application Support/vocabulary.json`; it contains the `Verify` group and its words. Relaunch and confirm the main card count went up by 3.
- **Effect.** Use the hotword clip (`$S fake-mic $U Packages/WaoCore/Tests/WaoCoreTests/Fixtures/hotword-redis.wav`, relaunch), run the mic test with and without a group containing `Redis`, and compare the two `result-text` values.
- **Reset.** Tap `คืนค่าเริ่มต้น` and confirm; the `Verify` group is gone from the screen and from `vocabulary.json`.
- **Proof.** Snapshot and screenshot of each screen plus `vocabulary.json` before and after.

## Gotchas

- Not yet driven by this skill; the add-word field and toggles are SwiftUI controls whose snapshot refs need checking on the first run.
- Saves are debounced 400 ms and forced when the app goes to the background; read `vocabulary.json` after a short wait, not immediately.
- `vocabulary.json` is absent until the first edit; absent means the bundled list.
- A long list warns `เกิน <n> คำ ...`; it is advice, not an error.
- Swipe left on a word deletes it (`แตะเพื่อแก้ · ปัดซ้ายเพื่อลบ`).
