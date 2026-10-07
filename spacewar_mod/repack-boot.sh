#!/bin/bash
# Build flashable artifacts from a compiled kernel Image.
#
#   ./repack-boot.sh v4        -> Spacewar-boot-sukisu-v4.img + Spacewar-SukiSUv4-SUSFSv2-5.4.289.zip
#   ./repack-boot.sh v155      -> Spacewar-boot-sukisu.img    + Spacewar-SukiSU-SUSFS-5.4.289.zip
#   ./repack-boot.sh rs        -> Spacewar-boot-resukisu-v4.img + Spacewar-ReSukiSU-SUSFSv2-5.4.289.zip
#
# Kernel source: kernel/build/Image
# Base ramdisk: stock NOS 3.2 boot image (stock/Spacewar_V3.2_stock_boot.img)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VARIANT="${1:-v4}"
IMAGE="$ROOT/kernel/build/Image"
STOCK="$ROOT/stock/Spacewar_V3.2_stock_boot.img"
WORK="$(mktemp -d /tmp/spacewar-repack.XXXXXX)"
MAGISKBOOT="${MAGISKBOOT:-$ROOT/tools/magiskboot}"

case "$VARIANT" in
    v4)   BOOT="$ROOT/Spacewar-boot-sukisu-v4.img"; ZIP="$ROOT/Spacewar-SukiSUv4-SUSFSv2-5.4.289.zip" ;;
    rs)   BOOT="$ROOT/Spacewar-boot-resukisu.img"; ZIP="$ROOT/Spacewar-ReSukiSU-SUSFSv2-5.4.289.zip" ;;
    v155) BOOT="$ROOT/Spacewar-boot-sukisu.img";    ZIP="$ROOT/Spacewar-SukiSU-SUSFS-5.4.289.zip" ;;
    *) echo "usage: $0 {v4|v155}" >&2; exit 1 ;;
esac

[ -f "$IMAGE" ] || { echo "missing $IMAGE (build first)" >&2; exit 1; }
[ -f "$STOCK" ] || { echo "missing stock base $STOCK" >&2; exit 1; }
[ -x "$MAGISKBOOT" ] || { echo "missing magiskboot at $MAGISKBOOT" >&2; exit 1; }

echo "[1/4] unpacking stock boot image"
cp "$STOCK" "$WORK/boot.img"
( cd "$WORK" && "$MAGISKBOOT" unpack boot.img >/dev/null )

echo "[2/4] replacing kernel"
cp "$IMAGE" "$WORK/kernel"

echo "[3/4] repacking"
( cd "$WORK" && "$MAGISKBOOT" repack boot.img new-boot.img >/dev/null )
cp "$WORK/new-boot.img" "$BOOT"

echo "[4/4] building AnyKernel3 zip"
cp "$IMAGE" "$ROOT/AnyKernel3/Image"
( cd "$ROOT/AnyKernel3" && rm -f "$ZIP" && zip -r9 "$ZIP" . -x "*.git*" >/dev/null )

rm -rf "$WORK"
echo "done:"
ls -lh "$BOOT" "$ZIP"
