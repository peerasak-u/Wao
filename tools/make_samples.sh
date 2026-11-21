#!/bin/sh
# Synthesises the Thai test clips in samples/ with the macOS Kanya voice.
set -eu
out="$(cd "$(dirname "$0")/.." && pwd)/samples"
mkdir -p "$out"
while IFS='|' read -r name text; do
  say -v Kanya -o "$out/$name.aiff" "$text"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$out/$name.aiff" "$out/$name.wav"
  rm "$out/$name.aiff"
  printf '%s\n' "$text" > "$out/$name.txt"
done <<'CLIPS'
greeting|สวัสดีครับ วันนี้อากาศดีมาก
food|ฉันอยากไปกินข้าวที่ร้านอาหารไทยใกล้บ้าน
trip|พรุ่งนี้เราจะไปเที่ยวทะเลกับครอบครัว
thanks|ขอบคุณ
CLIPS
