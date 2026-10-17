#!/usr/bin/env bash
# 主机（macOS）测试入口：编译 Core 纯逻辑并运行（07-validation §2）。
# 注意：macOS cfprefsd 按 UID 解析偏好文件，HOME 重定向无效；因此测试使用
# 每次运行随机生成的隔离域（编译期注入），避免读写真实用户偏好。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$(mktemp -d /tmp/metis-host-tests.XXXXXX)"
TEST_DOMAIN="com.lindo.metis.hosttest.$RANDOM$RANDOM"
cleanup() {
    rm -rf "$OUT_DIR"
    defaults delete "$TEST_DOMAIN" >/dev/null 2>&1 || true
}
trap cleanup EXIT

CC="$(command -v clang || true)"
[[ -n "$CC" ]] || { echo "error: clang not found" >&2; exit 1; }

TEST_BIN="$OUT_DIR/mt_module_gate_tests"
"$CC" -x objective-c -fobjc-arc -fmodules -g \
    -framework Foundation -framework CoreFoundation \
    -DMETIS_PACKAGE_VERSION='"host-test"' \
    -DMETIS_CONFIG_DOMAIN_OVERRIDE="\"$TEST_DOMAIN\"" \
    -I"$ROOT_DIR/Core" \
    "$ROOT_DIR/Tests/Host/MTModuleGateTests.m" \
    "$ROOT_DIR/Core/MTModuleGate.m" \
    "$ROOT_DIR/Core/MTConfigService.m" \
    "$ROOT_DIR/Core/MTLog.m" \
    "$ROOT_DIR/Core/MTPathResolver.m" \
    -o "$TEST_BIN"

"$TEST_BIN"
echo "==> host tests passed (domain: $TEST_DOMAIN)"
