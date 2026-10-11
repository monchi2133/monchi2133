#!/usr/bin/env bash
# AIロックキーパー（AILockKeeper.app）を組み立てる。UNIVERSAL=1 で arm64 + x86_64 のユニバーサルバイナリ。
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="build/AILockKeeper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Bastion" "$APP/Contents/MacOS/Bastion"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# アドホック署名（アクセシビリティ権限の付与に署名が必要）
codesign --force --deep --sign - "$APP"

(cd build && rm -f AILockKeeper.zip && ditto -c -k --keepParent AILockKeeper.app AILockKeeper.zip)
echo "Built: $(pwd)/$APP"
