#!/bin/bash
# 打包一个可直接下载安装的 CodexReset.app（未签名）。
# 用法：
#   ./make_release.sh            # 默认版本号
#   ./make_release.sh 1.2.0
#
# 产物放在 dist/（已在 .gitignore 里）：二进制不进仓库，走 GitHub Release。
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.1.0}"
APP_NAME="CodexReset"
DIST="dist"
STAGE="$DIST/stage"
ZIP="$DIST/$APP_NAME-macOS-$VERSION.zip"
NOTES="$DIST/RELEASE_NOTES.md"

rm -rf "$DIST"
mkdir -p "$STAGE"

# make_app.sh 负责编译、生成图标、组装 bundle。
# 给它一个临时目录当安装目标，别真的装到 /Applications。
INSTALL_DIR="$PWD/$STAGE" ./make_app.sh

APP="$STAGE/$APP_NAME.app"
[ -d "$APP" ] || { echo "错误：$APP 未生成" >&2; exit 1; }

# 重新做 ad-hoc 签名。make_app.sh 会优先用本机的 Apple Development 证书，
# 但那种证书一旦吊销，下载方的 macOS 会直接判定为恶意软件，而不是普通的
# 「开发者无法验证」；证书里还带着开发者邮箱，不该跟着安装包发出去。
echo "==> 重新 ad-hoc 签名（去掉本机证书与其中的邮箱）"
codesign --force --deep --sign - "$APP"
# 先取回输出再判断：grep -q 会提前关闭管道，codesign 收到 SIGPIPE，
# 在 pipefail 下会被当成失败
SIGN_INFO="$(codesign -dvv "$APP" 2>&1 || true)"
case "$SIGN_INFO" in
    *Signature=adhoc*) echo "    ad-hoc 签名已生效" ;;
    *) echo "错误：ad-hoc 签名未生效" >&2; exit 1 ;;
esac

# ditto 而非 zip：保留 macOS 的资源分支与签名结构
echo "==> 打包 $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
SIZE="$(du -h "$ZIP" | awk '{print $1}')"

# 发布说明连同 SHA 一起生成，避免手写时对不上。
# 模板用引号定界，shell 不做任何替换，占位符随后用 sed 填。
cat > "$NOTES" <<'TEMPLATE'
Fork of [boyso/codex-reset](https://github.com/boyso/codex-reset), maintained by
[Arturo UX](https://github.com/arthurglaizal). See
[FORK.md](https://github.com/arthurglaizal/codex-reset/blob/main/FORK.md) for the
full list of differences.

## Install

1. Download `__ZIPNAME__` below and unzip it.
2. Drag **CodexReset.app** into your Applications folder.
3. The first launch is refused, because the app is not signed with an Apple
   Developer ID. Open **System Settings → Privacy & Security**, scroll to the
   bottom, click **Open Anyway**, then launch it again. Only needed once.

Prefer building it yourself? `swift build -c release`, then `./make_app.sh`.

## What this build brings over the original

- Chats continued by hand are no longer reported as paused
- An ignore list, to keep a chat out of every list for good
- Auto-continue can target every paused chat without ticking anything
- Quota is reported as what is left, like Codex does, with vertical gauges
- Search, turn counts, a countdown to the next reset, and a dark mode

## Verify the download

```
shasum -a 256 __ZIPNAME__
```

Expected: `__SHA__`

Not an official OpenAI product.
TEMPLATE

ZIPNAME="$(basename "$ZIP")"
sed -i '' "s|__ZIPNAME__|$ZIPNAME|g; s|__SHA__|$SHA|g" "$NOTES"

cat <<SUMMARY

打包完成
  文件     $ZIP
  大小     $SIZE
  SHA-256  $SHA
  说明     $NOTES

下一步：
  gh release create v$VERSION "$ZIP" \\
      --title "CodexReset v$VERSION (fork)" \\
      --notes-file "$NOTES"
SUMMARY
