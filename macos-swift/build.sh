#!/bin/zsh
# TypingOverlay.app をビルドする（起動中なら終了してから作り直す）
set -e
cd "$(dirname "$0")"
APP=TypingOverlay.app

# アイコンは初回だけ生成
if [[ ! -f build/AppIcon.icns ]]; then
  mkdir -p build
  swift tools/makeicon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

pkill -x TypingOverlay 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/TypingOverlay" Sources/*.swift
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TypingOverlay</string>
  <key>CFBundleDisplayName</key><string>TypingOverlay</string>
  <key>CFBundleIdentifier</key><string>local.typingoverlay</string>
  <key>CFBundleExecutable</key><string>TypingOverlay</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built: $(pwd)/$APP"
