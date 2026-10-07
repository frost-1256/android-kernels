#!/bin/bash
# Restore the SukiSU Ultra 4.2.0 (builtin) + SUSFS v2.3.0 (backported to 5.4) tree state.
# After running this, build with: ./build_5.4_sukisu_v4.sh
set -euo pipefail

KERNEL_ROOT="$(cd "$(dirname "$0")/.." && pwd)/kernel"
BACKUP="$(cd "$(dirname "$0")" && pwd)/v230"
cd "$KERNEL_ROOT"

info(){ echo "[INFO] $*"; }

info "restoring stock tracked files"
git checkout -- .

info "applying kernel-side v2 backport patch"
git apply "$BACKUP/kernel-side-v2.patch"

info "staging v2 susfs files"
cp "$BACKUP/susfs.c" fs/susfs.c
cp "$BACKUP/susfs.h" include/linux/susfs.h
cp "$BACKUP/susfs_def.h" include/linux/susfs_def.h

info "restoring builtin KernelSU tree"
git -C KernelSU checkout -- .
git -C KernelSU checkout -q builtin
git -C KernelSU apply "$BACKUP/ksu-side-v2.patch"
cp "$BACKUP/selinux_hide_stub.c" KernelSU/kernel/feature/selinux_hide_stub.c
ln -sfn ../KernelSU/kernel drivers/kernelsu

info "done. Now run: ./build_5.4_sukisu_v4.sh"
