#!/bin/bash
# Restore the SukiSU v3.1.4 + SUSFS v1.5.5 (non-GKI 5.4) working tree state.
# After running this, build with: ./build_5.4_sukisu.sh
set -euo pipefail

KERNEL_ROOT="$(cd "$(dirname "$0")/.." && pwd)/kernel"
BACKUP="$(cd "$(dirname "$0")" && pwd)/v155"
cd "$KERNEL_ROOT"

info(){ echo "[INFO] $*"; }

info "restoring stock tracked files touched by the susfs hooks"
git checkout -- .

info "removing v2 susfs files"
rm -f fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h

info "staging v1 susfs files"
cp "$BACKUP/fs-susfs-v155.c" fs/susfs.c

info "applying kernel-side v1.5.5 patch"
git apply "$BACKUP/kernel-side-v155.patch"

info "restoring patched KernelSU v3.1.4 tree"
rm -rf KernelSU
mkdir -p KernelSU
tar xzf "$BACKUP/KernelSU-v314-patched.tar.gz" -C KernelSU --strip-components=1
ln -sfn ../KernelSU/kernel drivers/kernelsu

info "staging v1 susfs headers"
cp "$BACKUP/susfs.h" include/linux/susfs.h
cp "$BACKUP/susfs_def.h" include/linux/susfs_def.h

info "done. Now run: ./build_5.4_sukisu.sh"
