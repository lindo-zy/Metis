#!/usr/bin/env bash
# 包结构检查（07-validation §4）。对最终 deb 做元数据、布局、二进制依赖与
# 架构检查；任何一项失败即退出非零。
set -euo pipefail

usage() {
    echo "usage: package-check.sh <deb> <expected-version> <label>" >&2
    exit 2
}

[[ $# -eq 3 ]] || usage
DEB_PATH="$1"
EXPECTED_VERSION="$2"
LABEL="$3"

[[ -f "$DEB_PATH" ]] || { echo "error: deb not found: $DEB_PATH" >&2; exit 1; }

fail() { echo "error: $1" >&2; exit 1; }

EXTRACT_DIR="$(mktemp -d /tmp/metis-pkg-check.XXXXXX)"
trap 'rm -rf "$EXTRACT_DIR"' EXIT
dpkg-deb -x "$DEB_PATH" "$EXTRACT_DIR" || fail "dpkg-deb -x failed"

echo "==> [1/6] control 元数据"
PACKAGE_ID="$(dpkg-deb -f "$DEB_PATH" Package)"
VERSION="$(dpkg-deb -f "$DEB_PATH" Version)"
ARCH="$(dpkg-deb -f "$DEB_PATH" Architecture)"
DEPends="$(dpkg-deb -f "$DEB_PATH" Depends)"
CONFLICTS="$(dpkg-deb -f "$DEB_PATH" Conflicts)"
[[ "$PACKAGE_ID" == "com.lindo.metis" ]] || fail "Package mismatch: $PACKAGE_ID"
[[ "$VERSION" == "$EXPECTED_VERSION" ]] || fail "Version mismatch: $VERSION != $EXPECTED_VERSION"
[[ -n "$ARCH" ]] || fail "Architecture missing"
echo "com.lindo.metis ${VERSION} (${LABEL}) arch=${ARCH}"
grep -q 'com.pixpin.screenshot' <<<"$CONFLICTS" || fail "missing conflict com.pixpin.screenshot"
grep -q 'com.lindo.typex' <<<"$CONFLICTS" || fail "missing conflict com.lindo.typex"
grep -q 'com.lindo.kayokox' <<<"$CONFLICTS" || fail "missing conflict com.lindo.kayokox"

echo "==> [2/6] 布局与唯一入口"
DYLIB_DIR="$EXTRACT_DIR/Library/MobileSubstrate/DynamicLibraries"
for f in MetisSpringBoard MetisUIKit MetisPasteServices; do
    [[ -f "$DYLIB_DIR/$f.dylib" ]] || fail "missing $f.dylib"
    [[ -f "$DYLIB_DIR/$f.plist" ]] || fail "missing $f.plist"
done
[[ -f "$EXTRACT_DIR/Library/Metis/Frameworks/MetisCore.dylib" ]] || fail "missing MetisCore.dylib"
[[ -d "$EXTRACT_DIR/Library/PreferenceBundles/MetisPrefs.bundle" ]] || fail "missing MetisPrefs.bundle"
[[ -f "$EXTRACT_DIR/Library/PreferenceLoader/Preferences/Metis.plist" ]] || fail "missing PreferenceLoader Metis.plist"

PL_ENTRIES="$(ls "$EXTRACT_DIR/Library/PreferenceLoader/Preferences/" 2>/dev/null | grep -c '\.plist$' || true)"
[[ "$PL_ENTRIES" -eq 1 ]] || fail "PreferenceLoader entries: $PL_ENTRIES (expect 1)"
for forbidden in TypeX.plist TypeXPrefs.plist PixPin.plist PixPinPrefs.plist Kayoko.plist KayokoPreferences.plist; do
    [[ ! -e "$EXTRACT_DIR/Library/PreferenceLoader/Preferences/$forbidden" ]] || fail "legacy entry $forbidden installed"
done

echo "==> [3/6] 敏感/本地文件不得入包"
LISTING="$(dpkg-deb -c "$DEB_PATH")"
for forbidden in local.env notify.local.conf build-notify.local.conf .netrc KayokoHistory history-v4.sqlite; do
    ! grep -q "$forbidden" <<<"$LISTING" || fail "forbidden content in package: $forbidden"
done

echo "==> [4/6] 依赖与 install_name"
for dylib in \
    "$DYLIB_DIR/MetisSpringBoard.dylib" \
    "$DYLIB_DIR/MetisUIKit.dylib" \
    "$DYLIB_DIR/MetisPasteServices.dylib" \
    "$EXTRACT_DIR/Library/Metis/Frameworks/MetisCore.dylib" \
    "$EXTRACT_DIR/Library/PreferenceBundles/MetisPrefs.bundle/MetisPrefs"; do
    [[ -f "$dylib" ]] || fail "binary missing: $dylib"
    DEPS="$(otool -L "$dylib")"
    if [[ "$(basename "$dylib")" != "MetisCore.dylib" ]]; then
        grep -q '/var/jb/Library/Metis/Frameworks/MetisCore.dylib' <<<"$DEPS" \
            || fail "$(basename "$dylib") does not link MetisCore at /var/jb path"
    fi
done
CORE_INSTALL_NAME="$(otool -D "$EXTRACT_DIR/Library/Metis/Frameworks/MetisCore.dylib" | tail -1)"
[[ "$CORE_INSTALL_NAME" == "/var/jb/Library/Metis/Frameworks/MetisCore.dylib" ]] \
    || fail "MetisCore install_name wrong: $CORE_INSTALL_NAME"

echo "==> [5/6] 架构"
for dylib in "$DYLIB_DIR"/*.dylib "$EXTRACT_DIR/Library/Metis/Frameworks/MetisCore.dylib"; do
    INFO="$(lipo -info "$dylib")"
    grep -q 'arm64' <<<"$INFO" || fail "$(basename "$dylib") missing arm64: $INFO"
done

echo "==> [6/6] 版本一致性"
PREFS_INFO="$EXTRACT_DIR/Library/PreferenceBundles/MetisPrefs.bundle/Info.plist"
PREFS_VERSION="$(plutil -extract CFBundleShortVersionString raw "$PREFS_INFO" 2>/dev/null || true)"
[[ "$PREFS_VERSION" == "$EXPECTED_VERSION" ]] || fail "MetisPrefs version mismatch: $PREFS_VERSION"

echo "==> package check OK: $(basename "$DEB_PATH")"
