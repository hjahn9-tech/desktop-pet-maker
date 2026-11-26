#!/bin/bash
# 다마고치 메이커 빌드: ./build.sh  →  build/PetMaker.app (+ dist/PetMaker.zip)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/다마고치 메이커.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PetMaker "$APP/Contents/MacOS/PetMaker"
cp .build/release/PetRuntime "$APP/Contents/Resources/PetRuntime"   # 만들어질 다마고치 앱의 엔진
cp examples/mochi.png "$APP/Contents/Resources/mochi.png"

# 아이콘: 예시 캐릭터를 도트로 만든 그림
ICON=build/icon.iconset; mkdir -p "$ICON"
.build/release/PetMaker --cli examples/mochi.png --sheet build/icon_sheet.png >/dev/null
sips -c 64 64 --cropOffset 0 0 build/icon_sheet.png --out build/icon64.png >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon64.png --out "$ICON/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon64.png --out "$ICON/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICON" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON" build/icon_sheet.png build/icon64.png

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>다마고치 메이커</string>
  <key>CFBundleDisplayName</key><string>다마고치 메이커</string>
  <key>CFBundleIdentifier</key><string>local.desktoppet.maker</string>
  <key>CFBundleExecutable</key><string>PetMaker</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.image</string></array>
  </dict></array>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

mkdir -p dist
(cd build && ditto -c -k --keepParent "다마고치 메이커.app" ../dist/DesktopPetMaker.zip)
echo "완료: $APP  /  dist/DesktopPetMaker.zip"
