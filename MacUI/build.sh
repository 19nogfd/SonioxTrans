#!/bin/zsh
set -euo pipefail

UI_ROOT="${0:A:h}"
ROOT="${UI_ROOT:h}"
APP_NAME="SonioxTrans"
EXECUTABLE="SonioxTrans"
APP="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP/Contents"

if [[ ! -x "$ROOT/dist/server/server" ]]; then
  echo "请先运行 $ROOT/build_backend.sh"
  exit 1
fi

rm -rf "$ROOT/build"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/python_backend" "$CONTENTS/Resources/AppIcon.iconset" "$ROOT/build/module-cache"

swiftc \
  -target arm64-apple-macos14.0 \
  -module-cache-path "$ROOT/build/module-cache" \
  -O \
  -framework SwiftUI -framework AppKit -framework Combine \
  "$UI_ROOT"/Sources/*.swift \
  -o "$CONTENTS/MacOS/$EXECUTABLE"

cp -R "$ROOT/dist/server/." "$CONTENTS/Resources/python_backend/"

ICON_SOURCE="$UI_ROOT/Resources/AppIcon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$CONTENTS/Resources/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_SOURCE" --out "$CONTENTS/Resources/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$CONTENTS/Resources/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$CONTENTS/Resources/AppIcon.iconset"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>SonioxTrans</string>
  <key>CFBundleDisplayName</key><string>SonioxTrans</string>
  <key>CFBundleExecutable</key><string>SonioxTrans</string>
  <key>CFBundleIdentifier</key><string>com.youngjack.sonioxtrans</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>SonioxTrans 需要使用麦克风，将日语语音实时转换为中文字幕。</string>
  <key>NSHumanReadableCopyright</key><string>SonioxTrans</string>
</dict></plist>
PLIST

chmod +x "$CONTENTS/MacOS/$EXECUTABLE" "$CONTENTS/Resources/python_backend/server"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "应用构建完成：$APP"
