#!/bin/bash
# 把 release 二进制打包成 Statly.app（LSUIElement 菜单栏应用），ad-hoc 签名。
# 正式分发前改用 Developer ID 证书签名并公证。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.statly.app}"
BIN=".build/release/Statly"
APP="dist/Statly.app"

if [[ ! -f "$BIN" ]]; then
    echo "未找到 release 二进制，请先执行: swift build -c release" >&2
    exit 1
fi

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Statly"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Statly</string>
    <key>CFBundleDisplayName</key>
    <string>Statly</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>Statly</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026</string>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP"

echo "打包完成: $APP"
