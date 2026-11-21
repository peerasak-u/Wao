#!/bin/sh
# Builds Packages/WaoCore/Vendor/onnxruntime.xcframework (iOS device, iOS simulator, macOS)
# from Microsoft's signed NuGet package. The GitHub Swift package and download.onnxruntime.ai
# were unreachable in Nov 2026 (repo removed, CDN serving a mismatched TLS certificate),
# so the NuGet payload, pinned by hash, is the official source we can verify.
# Its LICENSE and ThirdPartyNotices.txt go into WaoInference's resources, since the app ships the binary.
set -eu

VERSION=1.32.0
SHA256=a9150bc2992cbbb6722070da9910e1ffa989a8bfc67bdd5bb8e745ca755641db
URL="https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/$VERSION/microsoft.ml.onnxruntime.$VERSION.nupkg"

root="$(cd "$(dirname "$0")/.." && pwd)"
vendor="$root/Packages/WaoCore/Vendor"
out="$vendor/onnxruntime.xcframework"
stamp="$vendor/onnxruntime.version"
cache="$root/.model-cache/onnxruntime-$VERSION"
notices="$root/Packages/WaoCore/Sources/WaoInference/Resources"

if [ -d "$out" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$VERSION" ] && [ -f "$notices/onnxruntime-ThirdPartyNotices.txt" ]; then
  echo "onnxruntime $VERSION already at $out"
  exit 0
fi

mkdir -p "$cache"
nupkg="$cache/ort.nupkg"
if [ ! -f "$nupkg" ] || [ "$(shasum -a 256 "$nupkg" | cut -d' ' -f1)" != "$SHA256" ]; then
  curl -sSfL -o "$nupkg.part" "$URL"
  mv "$nupkg.part" "$nupkg"
fi
actual="$(shasum -a 256 "$nupkg" | cut -d' ' -f1)"
[ "$actual" = "$SHA256" ] || { echo "sha256 mismatch: $actual" >&2; exit 1; }

mkdir -p "$notices"
unzip -p "$nupkg" LICENSE > "$notices/onnxruntime-LICENSE.txt"
unzip -p "$nupkg" ThirdPartyNotices.txt > "$notices/onnxruntime-ThirdPartyNotices.txt"

work="$cache/work"
rm -rf "$work"
mkdir -p "$work"
unzip -q "$nupkg" 'runtimes/ios/native/onnxruntime.xcframework.zip' 'runtimes/osx-arm64/native/libonnxruntime.dylib' -d "$work"
unzip -q "$work/runtimes/ios/native/onnxruntime.xcframework.zip" -d "$work/ios"

modulemap() {
  mkdir -p "$1"
  cat > "$1/module.modulemap" <<'EOF'
framework module onnxruntime {
  header "onnxruntime_c_api.h"
  export *
}
EOF
}

device="$work/ios/onnxruntime.xcframework/ios-arm64/onnxruntime.framework"
sim="$work/ios/onnxruntime.xcframework/ios-arm64_x86_64-simulator/onnxruntime.framework"
modulemap "$device/Modules"
modulemap "$sim/Modules"
# Xcode embeds this static framework with a stub binary built for the app's deployment target, but
# keeps this Info.plist; App Store upload rejects a MinimumOSVersion that differs (ITMS-90208).
ios_target="$(awk '/deploymentTarget:/ { getline; gsub(/[^0-9.]/, ""); print; exit }' "$root/project.yml")"
for fw in "$device" "$sim"; do
  plutil -replace MinimumOSVersion -string "$ios_target" "$fw/Info.plist"
done

mac="$work/macos/onnxruntime.framework"
mkdir -p "$mac/Versions/A/Resources"
cp "$work/runtimes/osx-arm64/native/libonnxruntime.dylib" "$mac/Versions/A/onnxruntime"
codesign --remove-signature "$mac/Versions/A/onnxruntime"
install_name_tool -id @rpath/onnxruntime.framework/Versions/A/onnxruntime "$mac/Versions/A/onnxruntime"
cp -R "$device/Headers" "$mac/Versions/A/Headers"
modulemap "$mac/Versions/A/Modules"
cat > "$mac/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>onnxruntime</string>
  <key>CFBundleIdentifier</key><string>com.microsoft.onnxruntime</string>
  <key>CFBundleName</key><string>onnxruntime</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF
ln -s A "$mac/Versions/Current"
for f in onnxruntime Headers Modules Resources; do ln -s "Versions/Current/$f" "$mac/$f"; done
codesign -s - "$mac"

rm -rf "$out"
mkdir -p "$vendor"
xcodebuild -create-xcframework -framework "$device" -framework "$sim" -framework "$mac" -output "$out" >/dev/null
echo "$VERSION" > "$stamp"
rm -rf "$work"
echo "onnxruntime $VERSION written to $out"
