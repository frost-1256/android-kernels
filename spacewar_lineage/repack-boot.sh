#!/bin/bash
# Repack the WitAqua 16.2 boot.img with a freshly built kernel Image.
#   ./repack-boot.sh [suffix]     e.g. ./repack-boot.sh resukisu
# Input : build/Image (from build_witaqua*.sh)
# Base  : stock/WitAqua-16.2-boot.img (ramdisk/vendor_boot are kept as-is)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="$ROOT/build/Image"
STOCK="$ROOT/stock/WitAqua-16.2-boot.img"
SUFFIX="${1:+$1}"
BOOT="$ROOT/WitAqua-16.2-boot-lineage23.2${SUFFIX:+-$SUFFIX}.img"
WORK="$(mktemp -d /tmp/witaqua-repack.XXXXXX)"
MAGISKBOOT="${MAGISKBOOT:-$ROOT/tools/magiskboot}"

[ -f "$IMAGE" ] || { echo "missing $IMAGE (build first)" >&2; exit 1; }
[ -f "$STOCK" ] || { echo "missing base $STOCK" >&2; exit 1; }
[ -x "$MAGISKBOOT" ] || { echo "missing magiskboot at $MAGISKBOOT" >&2; exit 1; }

echo "[1/4] unpacking base boot image"
cp "$STOCK" "$WORK/boot.img"
( cd "$WORK" && "$MAGISKBOOT" unpack boot.img >/dev/null )

echo "[2/4] replacing kernel"
rm -f "$WORK/kernel"
cp "$IMAGE" "$WORK/kernel"

echo "[3/4] repacking"
( cd "$WORK" && "$MAGISKBOOT" repack boot.img new-boot.img >/dev/null )
cp "$WORK/new-boot.img" "$BOOT"

echo "[4/4] verify"
VERIFY="$(mktemp -d /tmp/witaqua-verify.XXXXXX)"
cp "$BOOT" "$VERIFY/boot.img"
( cd "$VERIFY" && "$MAGISKBOOT" unpack boot.img >/dev/null && cmp -s kernel "$IMAGE" && echo "  kernel in repacked image matches build/Image" )
rm -rf "$WORK" "$VERIFY"
ls -lh "$BOOT"
