# Keyboard session

The keyboard cannot record, so the user opens a session in the app: the app holds the mic open in the background for the keyboard to use from other apps, and closes it after 5 minutes idle. The keyboard's mic key also opens the app through `wao://session` when no session is live.

## Sub-features

- `session-open` turns the session on from the card (`เปิด`); status reads `พร้อมฟัง · ปิดเองใน m:ss`.
- `session-close` turns it off (`ปิด`).
- `session-deeplink` opens the app and starts the session from `wao://session`.
- `session-status` reflects keyboard activity (`กำลังฟังจากคีย์บอร์ด`, `กำลังถอดเสียง`) and the mic test (`ไมค์ใช้ทดสอบอยู่`).
- `session-idle-timeout` closes the session after 5 minutes without dictation.

## How to get to it (user POV)

- Open เว่า and tap `เปิด` on the `เซสชันคีย์บอร์ด` card.
- Tap the mic on the เว่า keyboard in another app while no session is live; iOS opens เว่า, which starts the session.

## Driving it with agent-device

Preconditions:

- Baseline from `README.md`; app opened with `$AD open com.peerasak.wao --relaunch`; `$S state $U` shows `{"off":{}}`.

- **Open.** Tap the session pill. Run `$AD press 'id=session-toggle' --settle`. The card shows `พร้อมฟัง · ปิดเองใน 4:59` (counting down) and the pill reads `ปิด`. `$S state $U` shows `{"idle":{"expiresAt":...}}` about 300 s ahead.
- **Close.** Tap again. Run `$AD press 'id=session-toggle' --settle`. The pill reads `เปิด`; `$S state $U` shows `{"off":{}}`.
- **Deep link.** Close the app, then run `$AD open com.peerasak.wao wao://session`. The app comes up with the session on and `state.json` `idle`.
- **Idle timeout.** Open the session and wait past 5 minutes (`$AD wait 305000`). `state.json` returns to `{"off":{}}` and the pill reads `เปิด`.
- **Proof.** Capture `.ax.txt`, `.png` and `.bridge.txt` before opening, while idle, and after closing.

## Gotchas

- The model must be ready; without it the card says `ต้องดาวน์โหลดโมเดลก่อน จึงจะเปิดได้`.
- The countdown text changes every second, so a snapshot diff always shows it changing; assert on the prefix `พร้อมฟัง · ปิดเองใน`.
- On a simulator the background-audio keep-alive is not the device's: a session surviving in the background here does not prove it survives on an iPhone.
- The keyboard treats an `idle` state whose `expiresAt` is in the past as off.
