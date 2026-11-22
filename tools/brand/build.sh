#!/bin/sh
# Traces the hand-drawn marks in source/ into template SVG image sets for the app.
# The source sheets were generated with openai/gpt-image-2.5-sunburst; the boxes below pick one mark each.
# Needs potrace (brew install potrace) and sips.
set -eu
cd "$(dirname "$0")"
OUT=../../App/Assets.xcassets/Ink
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
printf '{ "info" : { "author" : "xcode", "version" : 1 }, "properties" : { "provides-namespace" : false } }\n' > "$OUT/Contents.json"

# name  sheet  y  x  height  width   (pixel box in the 1536x1024 sheet)
while read -r name sheet y x h w; do
  [ -z "$name" ] && continue
  sips -c "$h" "$w" --cropOffset "$y" "$x" "source/$sheet.png" --out "$TMP/$name.png" >/dev/null
  sips -s format bmp "$TMP/$name.png" --out "$TMP/$name.bmp" >/dev/null
  set="$OUT/$name.imageset"
  mkdir -p "$set"
  potrace "$TMP/$name.bmp" -s --tight --flat -k 0.5 -t 4 -O 0.4 -o "$set/$name.svg"
  printf '{\n  "images" : [ { "filename" : "%s.svg", "idiom" : "universal" } ],\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }\n}\n' "$name" > "$set/Contents.json"
  echo "$set/$name.svg"
done <<'BOXES'
MaiEk     strokes  66  176 232  92
InkTick   marks   180  465 270 245
InkTally  marks   200  800 230 305
InkUnderline marks 315 1180 75 305
InkArrow  marks   600   50 180 320
InkCircle marks   560  820 275 265
BOXES

# The app icon is the same stroke on dotted paper, rendered once per appearance.
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ICONS=../../App/Assets.xcassets/AppIcon.appiconset
for look in light dark; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=1024,1024 \
    --screenshot="$TMP/$look.png" "file://$(pwd)/icon.html?$look" >/dev/null 2>&1
  sips -s format png -s formatOptions default "$TMP/$look.png" --out "$ICONS/AppIcon-$look.png" >/dev/null
done
cat > "$ICONS/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "AppIcon-light.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "AppIcon-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
echo "$ICONS"
