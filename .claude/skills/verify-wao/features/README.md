# เว่า verification map

This directory is the maintained source for verifying the user-facing behavior of เว่า. Read the index before driving the app, then use the matching feature file as the recipe.

## Baseline preconditions

- A simulator opened through T3's `device_open`, with `U=<udid>` and `AD=<agent-device path>` set as in `../SKILL.md`.
- `S=.claude/skills/verify-wao/scripts/wao-verify`; `$S build` done for the current HEAD.
- `$S prepare $U` done: model seeded, microphone granted, `WAO_FAKE_MIC` set to `samples/greeting.wav` (expected words in `samples/greeting.txt`: `สวัสดีครับ วันนี้อากาศดีมาก`).
- `$S doctor $U` prints `doctor: OK`.
- Never drive a simulator another thread has open, or an app this run did not install.

## Driving conventions

- App UI goes through `$AD`. Prefer `id=` selectors from the table in `../SKILL.md`, then labels, then refs from `$AD snapshot -i`. Coordinates only for keyboard-extension keys, which have no accessibility nodes.
- Labels are Thai and literal. Copy them exactly, including `·` and `…`.
- Use `$AD wait <selector> <ms>` or `--settle` for state changes; transcription time varies with the clip length.
- After a mutation (vocabulary, keyboard settings), restore the baseline or re-run `$S prepare $U`.

## Proof and skip reporting

- Each proof lives in `$($S evidence <feature-id>)` and holds numbered `*.ax.txt` (snapshot), `*.png` (screenshot) and `*.bridge.txt` (`$S state $U`) for before, during and after.
- Mutation proof includes a second view: the stored file in the data or App Group container, or the screen after a relaunch.
- Record the feature ID, entry point and wav used with every artifact.
- Report an unreachable path with the attempted command and the unmet precondition. Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior, then exactly four H2 sections: `Sub-features`, `How to get to it (user POV)`, `Driving it with agent-device`, `Gotchas`. Keep implementation details out; name only user paths, stable handles, required state, commands and observable proof.

## Features

- [Mic test](./mic-test.md) — tap the hero waveform, speak, tap, read the transcription in the app. Proven by this skill's first run.
- [Keyboard session](./keyboard-session.md) — open the mic in the app so the keyboard can use it from other apps; idle timeout.
- [Keyboard dictation](./keyboard-dictation.md) — dictate into another app's text field through the เว่า keyboard.
- [Typing layouts](./typing-layouts.md) — Kedmanee, QWERTY and symbols, with and without Full Access.
- [Model download](./model-download.md) — fresh install, download, pause, resume, ready.
- [Vocabulary](./vocabulary.md) — groups, words, bulk import, reset; biases transcription toward English spellings.
