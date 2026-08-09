#!/bin/bash
# 打包发布：Release 构建 → 签名 → DMG →（有凭据则公证）→（加 --publish 则发 GitHub Release）
#
# 签名与公证按本机能力自动降级：
#   有 Developer ID Application 证书  → 正式签名 + Hardened Runtime + 时间戳
#   只有开发证书 / 没有证书            → ad-hoc 签名（用户首次打开需右键 → 打开）
#   配好 notarytool 钥匙串档案         → 自动公证并 staple
#
# 用法:
#   scripts/release.sh 0.1.0              打包到 dist/，不发布
#   scripts/release.sh 0.1.0 --publish    打包并创建 GitHub Release（会推 tag，公开可见）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
PUBLISH="${2:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-statly-notary}"

if [[ -z "$VERSION" ]]; then
    echo "用法: scripts/release.sh <版本号> [--publish]" >&2
    exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "版本号需形如 1.2.3，收到: $VERSION" >&2
    exit 1
fi

APP="dist/Statly.app"
DMG="dist/Statly-$VERSION.dmg"
BUILD_NUMBER="$(git rev-list --count HEAD)"

echo "==> 检查工作区"
if [[ -n "$(git status --porcelain)" ]]; then
    echo "工作区有未提交的改动，先提交再发布：" >&2
    git status --short >&2
    exit 1
fi

echo "==> 运行测试"
swift test 2>&1 | tail -1

echo "==> 构建 Release（版本 $VERSION，构建号 $BUILD_NUMBER）"
xcodegen generate >/dev/null
xcodebuild -project Statly.xcodeproj -scheme Statly -configuration Release \
    -derivedDataPath .build/xcode \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build 2>&1 | grep -E "(error|warning: unable|BUILD)" || true

rm -rf dist && mkdir -p dist
cp -R .build/xcode/Build/Products/Release/Statly.app "$APP"

# 签名：优先用分发证书，没有就退回 ad-hoc
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/' || true)"
if [[ -n "$IDENTITY" ]]; then
    echo "==> 正式签名: $IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
    SIGNED=yes
else
    echo "==> 未找到 Developer ID Application 证书，使用 ad-hoc 签名"
    echo "    （用户首次打开需右键 → 打开，或执行 xattr -d com.apple.quarantine）"
    codesign --force --deep --sign - "$APP"
    SIGNED=no
fi
codesign --verify --strict "$APP" && echo "    签名校验通过"

echo "==> 制作 DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Statly $VERSION" -srcfolder "$STAGING" \
    -ov -format UDZO -quiet "$DMG"

if [[ "$SIGNED" == "yes" ]]; then
    codesign --force --sign "$IDENTITY" "$DMG"
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "==> 公证中（可能数分钟）"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        echo "    公证完成并已 staple"
    else
        echo "==> 跳过公证：未配置钥匙串档案 $NOTARY_PROFILE"
        echo "    配置方法: xcrun notarytool store-credentials $NOTARY_PROFILE \\"
        echo "                --apple-id <你的AppleID> --team-id <团队ID> --password <应用专用密码>"
    fi
fi

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
SIZE="$(du -h "$DMG" | awk '{print $1}')"
echo
echo "==> 完成: $DMG（$SIZE）"
echo "    SHA256: $SHA"

if [[ "$PUBLISH" != "--publish" ]]; then
    echo
    echo "尚未发布。确认无误后执行："
    echo "    scripts/release.sh $VERSION --publish"
    exit 0
fi

echo "==> 创建 GitHub Release v$VERSION"
PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [[ -n "$PREV_TAG" ]]; then
    CHANGES="$(git log --pretty='- %s' "$PREV_TAG"..HEAD)"
else
    CHANGES="$(git log --pretty='- %s' -20)"
fi

NOTES_FILE="$(mktemp)"
cat > "$NOTES_FILE" <<EOF
## 变更

$CHANGES

## 安装

下载 DMG，把 Statly 拖进「应用程序」。
EOF
if [[ "$SIGNED" != "yes" ]]; then
    cat >> "$NOTES_FILE" <<'EOF'

> 本版本未经 Apple 公证，首次打开需 **右键点击 App → 打开 → 再次确认**，
> 或在终端执行 `xattr -d com.apple.quarantine /Applications/Statly.app`。

EOF
fi
cat >> "$NOTES_FILE" <<EOF

要求 macOS 13 及以上。

SHA256: \`$SHA\`
EOF

git tag -a "v$VERSION" -m "Statly $VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$DMG" --title "Statly $VERSION" --notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"
echo "==> 已发布: $(gh release view "v$VERSION" --json url -q .url)"
