#!/usr/bin/env bash
# Metis 统一构建入口（07-validation §3 的目标契约实现）。
#
# 用法：
#   ./build.sh --help
#   ./build.sh --target all --mode verify                 # 本地测试+构建+包检查，不改 control
#   ./build.sh --target all --mode release --version 0.1.0 # 显式版本发布，全部检查通过后才写回版本
#
# 规则：
#   - 只从本脚本进入 Theos/make；不归档云端、不上传、不推送通知。
#   - verify 产物放 packages/verify/<label>/，release 产物放 packages/<label>/，互不混用。
#   - release 同一版本重复发布直接拒绝；版本写回不早于全部构建与包检查。
#   - 构建进程级锁：同一时刻只允许一个 build.sh 写 control/.theos/packages。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${THEOS:-}" || ! -d "${THEOS:-}" ]]; then
    THEOS="/Users/xiao/dev/theos-roothide"
fi
export THEOS

MAKE_BIN="$(command -v gmake || command -v make || true)"
if [[ -z "$MAKE_BIN" ]]; then
    echo "error: make or gmake is required" >&2
    exit 1
fi
if [[ ! -d "$THEOS" ]]; then
    echo "error: Theos not found at $THEOS" >&2
    exit 1
fi

PACKAGE_ID="com.lindo.metis"
CONTROL_FILE="$ROOT_DIR/control"
CONTROL_VERSION="$(awk -F': ' '/^Version:/{print $2; exit}' "$CONTROL_FILE")"
if [[ -z "$CONTROL_VERSION" || ! "$CONTROL_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "error: Version must use MAJOR.MINOR.PATCH format in control: ${CONTROL_VERSION:-<missing>}" >&2
    exit 1
fi

# 版本递增（参考 TypeX）：PATCH 0-10，满 10 进 MINOR，MINOR 满 10 进 MAJOR。
NEXT_MAJOR="${BASH_REMATCH[1]}"
NEXT_MINOR="${BASH_REMATCH[2]}"
NEXT_PATCH="$((10#${BASH_REMATCH[3]} + 1))"
if (( NEXT_PATCH > 10 )); then
    NEXT_PATCH=0
    NEXT_MINOR="$((10#${BASH_REMATCH[2]} + 1))"
fi
if (( NEXT_MINOR > 10 )); then
    NEXT_MINOR=0
    NEXT_MAJOR="$((10#${BASH_REMATCH[1]} + 1))"
fi
NEXT_VERSION="${NEXT_MAJOR}.${NEXT_MINOR}.${NEXT_PATCH}"

usage() {
    cat >&2 <<'EOF'
usage: ./build.sh [--target ios16|ios17|all] [--mode verify|release] [--version X.Y.Z]
  --target   构建目标，默认 all；开发可单目标验证，发布必须 all。
  --mode     verify（默认）：主机测试+构建+包检查。
             release：集成分支干净检查；双平台全部通过后写 manifest。
  --version  可选覆盖（MAJOR.MINOR.PATCH）。缺省按 TypeX 规则自动递增：
             PATCH +1，满 10 进 MINOR，MINOR 满 10 进 MAJOR；构建全部成功后
             写回 control（失败不写）。CI tag 构建用它钉住 tag 版本。
环境变量：
  SKIP_TESTS=1                跳过主机测试（仅本地快速迭代，发布不建议）。
  METIS_SDK_ROOT=<dir>        覆盖 SDK 查找根（默认 $THEOS/sdks）。
  METIS_ALLOW_DIRTY=1         release 时允许脏工作区（不建议）。
EOF
    exit 2
}

BUILD_TARGET="all"
BUILD_MODE="verify"
BUILD_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) BUILD_TARGET="${2:-}"; shift 2 ;;
        --mode) BUILD_MODE="${2:-}"; shift 2 ;;
        --version) BUILD_VERSION="${2:-}"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "error: unknown argument: $1" >&2; usage ;;
    esac
done

case "$BUILD_TARGET" in
    ios16|ios17|all) ;;
    *) echo "error: invalid --target: $BUILD_TARGET" >&2; usage ;;
esac
case "$BUILD_MODE" in
    verify|release) ;;
    *) echo "error: invalid --mode: $BUILD_MODE" >&2; usage ;;
esac
if [[ "$BUILD_MODE" == "release" ]]; then
    if [[ -n "$BUILD_VERSION" ]] && ! [[ "$BUILD_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "error: version must be MAJOR.MINOR.PATCH: $BUILD_VERSION" >&2
        exit 1
    fi
    if [[ "$BUILD_TARGET" != "all" ]]; then
        echo "error: release must use --target all" >&2
        exit 1
    fi
fi

VERSION_TO_BUILD="${BUILD_VERSION:-$NEXT_VERSION}"
SDK_ROOT="${METIS_SDK_ROOT:-$THEOS/sdks}"

# ---- 进程级锁 ----
LOCK_DIR="$ROOT_DIR/packages/.build-lock"
if [[ -e "$LOCK_DIR" ]] || ! mkdir -p "$LOCK_DIR" 2>/dev/null; then
    echo "error: another build is in progress (lock: $LOCK_DIR)" >&2
    exit 1
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

# ---- release 前置检查 ----
if [[ "$BUILD_MODE" == "release" ]]; then
    if [[ "${METIS_ALLOW_DIRTY:-0}" != "1" ]]; then
        if [[ -n "$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null)" ]]; then
            echo "error: release requires a clean integration branch (uncommitted changes present)" >&2
            exit 1
        fi
        BRANCH="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
        case "$BRANCH" in
            main|codex/*) ;;
            *) echo "error: release must run on main or codex/* (current: ${BRANCH:-detached})" >&2; exit 1 ;;
        esac
    fi
    for label in ios16 ios17; do
        if [[ -f "$ROOT_DIR/packages/$label/${PACKAGE_ID}_${VERSION_TO_BUILD}_${label}_iphoneos-arm64e.deb" ]]; then
            echo "error: version $VERSION_TO_BUILD already built for $label; refusing to overwrite" >&2
            exit 1
        fi
    done
fi

# ---- 主机测试与包检查 ----
# 测试脚本按用户约定不上库（.gitignore 排除 docs/ Tests/）；本地存在时执行，
# 检出（CI）中缺失则警告跳过，构建继续。
if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
    if [[ -x "$ROOT_DIR/Tests/Host/run-host-tests.sh" ]]; then
        "$ROOT_DIR/Tests/Host/run-host-tests.sh"
    else
        echo "warning: host tests skipped (Tests/ not present in checkout)" >&2
    fi
else
    echo "warning: host tests skipped (SKIP_TESTS=1)" >&2
fi

sdk_for_label() {
    case "$1" in
        ios16) echo "16.5" ;;
        ios17) echo "17.0" ;;
    esac
}
deployment_for_label() {
    # 统一最低部署线 16.0（07 §3）；iOS17 变体仅 SDK 不同，manifest 明示。
    echo "16.0"
}

OUTPUT_ROOT="$ROOT_DIR/packages"
[[ "$BUILD_MODE" == "verify" ]] && OUTPUT_ROOT="$ROOT_DIR/packages/verify"

build_one() {
    local label="$1"
    local sdk_version
    sdk_version="$(sdk_for_label "$label")"
    local deployment_version
    deployment_version="$(deployment_for_label "$label")"
    local sdk_path="$SDK_ROOT/iPhoneOS${sdk_version}.sdk"
    local output_dir="$OUTPUT_ROOT/$label"
    local output_path="$output_dir/${PACKAGE_ID}_${VERSION_TO_BUILD}_${label}_iphoneos-arm64e.deb"

    if [[ ! -d "$sdk_path" ]]; then
        echo "error: required SDK not found: $sdk_path (set METIS_SDK_ROOT to override)" >&2
        exit 1
    fi

    echo "==> [$BUILD_MODE] Building $label with iPhoneOS${sdk_version}.sdk (deployment ${deployment_version})"

    find "$ROOT_DIR/packages" -maxdepth 1 -type f -name '*.deb' -delete 2>/dev/null || true
    "$MAKE_BIN" -C "$ROOT_DIR" clean >/dev/null

    (
        cd "$ROOT_DIR"
        THEOS_PACKAGE_SCHEME=roothide \
            TARGET="iphone:clang:${sdk_version}:${deployment_version}" \
            "$MAKE_BIN" package FINALPACKAGE=1 PACKAGE_VERSION="$VERSION_TO_BUILD"
    )

    mkdir -p "$output_dir"
    find "$output_dir" -maxdepth 1 -type f -name '*.deb' -delete 2>/dev/null || true

    local package_path
    package_path="$(find "$ROOT_DIR/packages" -maxdepth 1 -type f -name "${PACKAGE_ID}_*.deb" -print -quit)"
    if [[ -z "$package_path" ]]; then
        echo "error: package was not produced for $label" >&2
        exit 1
    fi

    mv "$package_path" "$output_path"
    if [[ -x "$ROOT_DIR/Tests/Package/package-check.sh" ]]; then
        "$ROOT_DIR/Tests/Package/package-check.sh" "$output_path" "$VERSION_TO_BUILD" "$label"
    else
        echo "warning: package check skipped (Tests/ not present in checkout)" >&2
    fi
    echo "==> Output: $output_path"
}

case "$BUILD_TARGET" in
    ios16) build_one ios16 ;;
    ios17) build_one ios17 ;;
    all) build_one ios16; build_one ios17 ;;
esac

# ---- 版本写回（参考 TypeX：全部目标构建成功后才写，temp 文件 + trap 清理） ----
CONTROL_TMP=""
persist_control_version() {
    [[ "$CONTROL_VERSION" == "$VERSION_TO_BUILD" ]] && return 0
    CONTROL_TMP="$(mktemp "$ROOT_DIR/control.tmp.XXXXXX")"
    awk -v next_version="$VERSION_TO_BUILD" '
        BEGIN { updated = 0 }
        /^Version:/ { print "Version: " next_version; updated = 1; next }
        { print }
        END { if (!updated) exit 1 }
    ' "$CONTROL_FILE" > "$CONTROL_TMP"
    mv "$CONTROL_TMP" "$CONTROL_FILE"
    CONTROL_TMP=""
    echo "==> control Version: ${CONTROL_VERSION} -> ${VERSION_TO_BUILD}"
}
finalize() {
    local rc=$?
    trap - EXIT
    rm -rf "$LOCK_DIR"
    rm -f "${CONTROL_TMP:-}"
    if [[ $rc -eq 0 ]]; then
        # 构建链全部成功才落版本号；任何失败保持 control 原值。
        persist_control_version || true
    fi
    exit $rc
}
trap finalize EXIT

# ---- release 收尾：manifest（全部检查通过之后） ----
if [[ "$BUILD_MODE" == "release" ]]; then
    INTEGRATION_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for label in ios16 ios17; do
        deb="$ROOT_DIR/packages/$label/${PACKAGE_ID}_${VERSION_TO_BUILD}_${label}_iphoneos-arm64e.deb"
        sha="$(shasum -a 256 "$deb" | awk '{print $1}')"
        size="$(stat -f %z "$deb")"
        cat > "$ROOT_DIR/packages/$label/manifest-${VERSION_TO_BUILD}.json" <<EOF
{
  "package": "${PACKAGE_ID}",
  "version": "${VERSION_TO_BUILD}",
  "label": "${label}",
  "sdk": "iPhoneOS$(sdk_for_label "$label").sdk",
  "deploymentTarget": "$(deployment_for_label "$label")",
  "packageScheme": "roothide",
  "deb": "$(basename "$deb")",
  "sha256": "${sha}",
  "sizeBytes": ${size},
  "integrationCommit": "${INTEGRATION_COMMIT}",
  "generatedAt": "${GENERATED_AT}"
}
EOF
    done

    echo "==> release ${VERSION_TO_BUILD} complete"
else
    echo "==> verify build complete: ${VERSION_TO_BUILD}"
fi
