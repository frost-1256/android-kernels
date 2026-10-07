#!/bin/bash
# Build LineageOS lineage-23.2 kernel for Nothing Phone (1) spacewar (SM7325).
# Target: WitAqua 16.2 (LineageOS 23.2 based) boot.img repack.
#
#   ./build_witaqua.sh            # defconfig + Image
#
# Source : kernel/  (LineageOS/android_kernel_nothing_sm7325, branch witaqua)
# Toolchain: ~/toolchains/clang-r563880c (AOSP clang 21.0.0, matches WitAqua kernel string)
# Config : vendor/lahaina-qgki_defconfig + vendor/debugfs.config (same as LineageOS BoardConfig)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
KERNEL="$ROOT/kernel"
OUT="$ROOT/out"
JOBS="$(nproc)"
CLANG_DIR="${CLANG_DIR:-$HOME/toolchains/clang-r563880c}"

DEFCONFIG="vendor/lahaina-qgki_defconfig"
EXTRA_CONFIGS=(vendor/debugfs.config)
VENDOR_RELEASE="5.4.302-qgki-g7ed191eb55b6"

[ -f "$KERNEL/Makefile" ] && [ -d "$KERNEL/arch/arm64" ] || { echo "kernel root invalid: $KERNEL" >&2; exit 1; }
[ -x "$CLANG_DIR/bin/clang" ] || { echo "clang not found: $CLANG_DIR/bin/clang" >&2; exit 1; }
export PATH="$CLANG_DIR/bin:$PATH"

# Pin the release string to the lineage-23.2 base commit so the WitAqua ROM's
# vendor module vermagic keeps matching regardless of local commits.
echo "-g7ed191eb55b6" > "$KERNEL/.scmversion"

echo "== clang: $("$CLANG_DIR/bin/clang" --version | head -1)"

CC_ARG=()
if command -v ccache >/dev/null 2>&1; then
    export CCACHE_COMPRESS=1
    export CCACHE_SLOPPINESS=time_macros,include_file_ctime,include_file_mtime,file_stat_matches
    export CCACHE_MAXSIZE=20G
    CC_ARG=(CC="ccache clang")
fi

MAKE=(make -C "$KERNEL" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 "${CC_ARG[@]}")

echo "[1/3] generating .config"
"${MAKE[@]}" "$DEFCONFIG" "${EXTRA_CONFIGS[@]}"

echo "[2/3] building Image (-j$JOBS)"
"${MAKE[@]}" -j"$JOBS" Image

echo "[3/3] copying artifacts"
mkdir -p "$ROOT/build"
cp "$OUT/arch/arm64/boot/Image" "$ROOT/build/Image"
"${MAKE[@]}" -s kernelrelease > "$ROOT/build/kernelrelease.txt"
release="$(cat "$ROOT/build/kernelrelease.txt")"
[ "$release" = "$VENDOR_RELEASE" ] || {
    echo "kernelrelease '$release' != '$VENDOR_RELEASE' (vendor modules may not load)" >&2
    [ "${ALLOW_VERMAGIC_MISMATCH:-0}" = "1" ] || exit 1
}
ls -lh "$ROOT/build/Image"
echo "kernelrelease: $release"
