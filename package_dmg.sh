#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/build/SonioxTrans.app"
STAGE="$ROOT/build/dmg-stage"
OUTPUT="/Users/mac/Downloads/SonioxTrans.dmg"

if [[ ! -d "$APP" ]]; then
  echo "请先运行 $ROOT/MacUI/build.sh"
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/SonioxTrans.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" <<'TXT'
SonioxTrans 安装方法

将 SonioxTrans.app 拖到右侧的 Applications 文件夹。
首次打开时，请填写自己的 Soniox API Key，并选择与项目一致的地域。
TXT

rm -f "$OUTPUT"
hdiutil create \
  -volname "SonioxTrans" \
  -srcfolder "$STAGE" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
echo "DMG 构建完成：$OUTPUT"
