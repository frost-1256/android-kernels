#!/usr/bin/env bash
# Build a GKI (android14-6.1) kernel for Pixel 8a (akita) with SukiSU Ultra + SUSFS.
# Intended to run on an Ubuntu GitHub Actions runner; it downloads everything itself.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORK="${WORKDIR:-$ROOT/.work/akita}"
ART="${ARTIFACT_DIR:-$ROOT/akita_sukisu/artifacts}"

KERNEL_REF="${KERNEL_REF:-android14-6.1-2026-09}"
KERNEL_REPO="${KERNEL_REPO:-https://android.googlesource.com/kernel/common.git}"

SUKISU_REF="${SUKISU_REF:-builtin}"
SUKISU_COMMIT="${SUKISU_COMMIT:-}"
SUKISU_SETUP_URL="${SUKISU_SETUP_URL:-https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh}"

SUSFS_REPO="${SUSFS_REPO:-https://github.com/ShirkNeko/susfs4ksu.git}"
SUSFS_REF="${SUSFS_REF:-gki-android14-6.1}"
SUSFS_COMMIT="${SUSFS_COMMIT:-}"
SUSFS_PATCH_NAME="${SUSFS_PATCH_NAME:-50_add_susfs_in_gki-android14-6.1.patch}"

KPM="${KPM:-false}"
CLANG_VERSION="${CLANG_VERSION:-clang-r487747c}"
CLANG_ARCHIVE_REF="${CLANG_ARCHIVE_REF:-android14-release}"

AK3_REPO="${AK3_REPO:-https://github.com/deepongi-labs/AnyKernel3-p8a.git}"
AK3_REF="${AK3_REF:-gki-2.0}"
BOOT_PARTITION_SIZE="${BOOT_PARTITION_SIZE:-67108864}"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

mkdir -p "$WORK" "$ART"
rm -rf "${ART:?}"/*
KERNEL_DIR="$WORK/common"

log "Build inputs"
cat <<EOF
  kernel repo    : $KERNEL_REPO
  kernel ref     : $KERNEL_REF
  SukiSU ref     : $SUKISU_REF ${SUKISU_COMMIT:+($SUKISU_COMMIT)}
  SUSFS repo/ref : $SUSFS_REPO / $SUSFS_REF ${SUSFS_COMMIT:+($SUSFS_COMMIT)}
  KPM            : $KPM
  clang          : $CLANG_VERSION ($CLANG_ARCHIVE_REF)
EOF

log "Clone kernel source ($KERNEL_REF)"
if [[ ! -d "$KERNEL_DIR/.git" ]]; then
  git clone --depth=1 --single-branch -b "$KERNEL_REF" "$KERNEL_REPO" "$KERNEL_DIR"
else
  git -C "$KERNEL_DIR" fetch --depth=1 origin "$KERNEL_REF"
  git -C "$KERNEL_DIR" checkout -B build FETCH_HEAD
fi

log "Install AOSP clang $CLANG_VERSION"
CLANG_ROOT="$WORK/toolchain"
if [[ ! -x "$CLANG_ROOT/bin/clang" && ! -x "$CLANG_ROOT/$CLANG_VERSION/bin/clang" ]]; then
  mkdir -p "$CLANG_ROOT"
  curl -fL --retry 3 --retry-delay 5 \
    "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${CLANG_ARCHIVE_REF}/${CLANG_VERSION}.tar.gz" \
    -o "$WORK/clang.tar.gz"
  tar -xzf "$WORK/clang.tar.gz" -C "$CLANG_ROOT"
  rm -f "$WORK/clang.tar.gz"
fi
if [[ ! -x "$CLANG_ROOT/bin/clang" && -x "$CLANG_ROOT/$CLANG_VERSION/bin/clang" ]]; then
  CLANG_ROOT="$CLANG_ROOT/$CLANG_VERSION"
fi
[[ -x "$CLANG_ROOT/bin/clang" ]] || die "clang not found under $CLANG_ROOT"
export PATH="$CLANG_ROOT/bin:$PATH"
clang --version | head -n 3

log "Integrate SukiSU Ultra ($SUKISU_REF)"
if [[ ! -d "$KERNEL_DIR/KernelSU/.git" ]]; then
  ( cd "$KERNEL_DIR" && curl -fsSL "$SUKISU_SETUP_URL" | bash -s "$SUKISU_REF" )
fi
if [[ -n "$SUKISU_COMMIT" ]]; then
  git -C "$KERNEL_DIR/KernelSU" fetch --depth=1 origin "$SUKISU_COMMIT" \
    || git -C "$KERNEL_DIR/KernelSU" fetch origin "$SUKISU_COMMIT"
  git -C "$KERNEL_DIR/KernelSU" checkout --detach "$SUKISU_COMMIT"
fi
[[ -L "$KERNEL_DIR/drivers/kernelsu" ]] || die "SukiSU setup did not create drivers/kernelsu"
grep -q 'kernelsu' "$KERNEL_DIR/drivers/Makefile" || die "SukiSU setup did not patch drivers/Makefile"
grep -q 'drivers/kernelsu/Kconfig' "$KERNEL_DIR/drivers/Kconfig" || die "SukiSU setup did not patch drivers/Kconfig"
git -C "$KERNEL_DIR/KernelSU" log -1 --oneline

log "Integrate SUSFS ($SUSFS_REF)"
SUSFS_DIR="$WORK/susfs4ksu"
if [[ ! -d "$SUSFS_DIR/.git" ]]; then
  git clone --depth=1 --single-branch -b "$SUSFS_REF" "$SUSFS_REPO" "$SUSFS_DIR"
fi
if [[ -n "$SUSFS_COMMIT" ]]; then
  git -C "$SUSFS_DIR" fetch --depth=1 origin "$SUSFS_COMMIT" \
    || git -C "$SUSFS_DIR" fetch origin "$SUSFS_COMMIT"
  git -C "$SUSFS_DIR" checkout --detach "$SUSFS_COMMIT"
fi
git -C "$SUSFS_DIR" log -1 --oneline

SUSFS_PATCH="$SUSFS_DIR/kernel_patches/$SUSFS_PATCH_NAME"
[[ -f "$SUSFS_PATCH" ]] || die "SUSFS patch not found: $SUSFS_PATCH"
cp -f "$SUSFS_DIR"/kernel_patches/fs/* "$KERNEL_DIR/fs/"
cp -f "$SUSFS_DIR"/kernel_patches/include/linux/* "$KERNEL_DIR/include/linux/"
if ! ( cd "$KERNEL_DIR" && patch -p1 --fuzz=3 --no-backup-if-mismatch < "$SUSFS_PATCH" ); then
  find "$KERNEL_DIR" -name '*.rej' -print -exec cat {} \;
  die "SUSFS kernel patch failed (try another KERNEL_REF)"
fi
if find "$KERNEL_DIR" -name '*.rej' -print -quit | grep -q .; then
  find "$KERNEL_DIR" -name '*.rej' -print -exec cat {} \;
  die "SUSFS patch left rejected hunks"
fi

# SUSFS requires this for vendor Wi-Fi modules on 6.1 GKI.
rm -f "$KERNEL_DIR"/android/abi_gki_protected_exports_*

log "Apply kernel config fragment"
FRAGMENT="$ROOT/akita_sukisu/akita.fragment"
[[ -f "$FRAGMENT" ]] || die "fragment not found: $FRAGMENT"
cp "$FRAGMENT" "$WORK/akita.fragment"
if [[ "$KPM" == "true" ]]; then
  sed -i 's/^# CONFIG_KPM is not set$/CONFIG_KPM=y/' "$WORK/akita.fragment"
fi
cat "$WORK/akita.fragment" >> "$KERNEL_DIR/arch/arm64/configs/gki_defconfig"

# Avoid a "-dirty" suffix in uname (the tree always has local changes here).
sed -i "s/printf '%s' -dirty/printf '%s' ''/g" "$KERNEL_DIR/scripts/setlocalversion"

log "Build GKI Image"
export ARCH=arm64 SUBARCH=arm64 LLVM=1 LLVM_IAS=1
export CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
       OBJDUMP=llvm-objdump STRIP=llvm-strip READELF=llvm-readelf
(
  cd "$KERNEL_DIR"
  make O=out gki_defconfig
  make O=out -j"$(nproc)" Image
)

CONFIG_OUT="$KERNEL_DIR/out/.config"
log "Verify required configs"
for opt in \
  CONFIG_KSU=y \
  CONFIG_KSU_SUSFS=y \
  CONFIG_KSU_SUSFS_SUS_PATH=y \
  CONFIG_KSU_SUSFS_SUS_MOUNT=y \
  CONFIG_KSU_SUSFS_SUS_KSTAT=y \
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y \
  CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y \
  CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y \
  CONFIG_KSU_SUSFS_OPEN_REDIRECT=y \
  CONFIG_KSU_SUSFS_SUS_MAP=y \
  CONFIG_TMPFS_XATTR=y \
  CONFIG_TMPFS_POSIX_ACL=y \
  CONFIG_LTO_CLANG_THIN=y
do
  grep -qx "$opt" "$CONFIG_OUT" || die "missing config: $opt"
done
if [[ "$KPM" == "true" ]]; then
  grep -qx 'CONFIG_KPM=y' "$CONFIG_OUT" || die "KPM requested but CONFIG_KPM is not enabled"
fi

IMAGE="$KERNEL_DIR/out/arch/arm64/boot/Image"
[[ -f "$IMAGE" ]] || die "Image not found: $IMAGE"

if [[ "$KPM" == "true" ]]; then
  log "Patch Image for KPM"
  curl -fsSL "https://raw.githubusercontent.com/ShirkNeko/SukiSU_patch/refs/heads/main/kpm/patch_linux" \
    -o "$WORK/patch_linux"
  chmod +x "$WORK/patch_linux"
  ( cd "$KERNEL_DIR/out/arch/arm64/boot" && "$WORK/patch_linux" )
  [[ -f "$KERNEL_DIR/out/arch/arm64/boot/oImage" ]] \
    || die "KPM patch did not produce oImage"
  mv "$KERNEL_DIR/out/arch/arm64/boot/oImage" "$IMAGE"
fi

KERNEL_RELEASE="$(cd "$KERNEL_DIR" && make -s O=out kernelrelease)"
SAFE_RELEASE="$(printf '%s' "$KERNEL_RELEASE" | tr '/ ' '__')"
BASE="akita-sukisu-susfs-${SAFE_RELEASE}"

log "Package artifacts ($BASE)"
cp "$IMAGE" "$ART/${BASE}-Image"

# Raw kernel-only boot image (header v4; Pixel 8a keeps init_boot separate).
log "Create boot.img"
MKBOOT_DIR="$WORK/mkbootimg"
if [[ ! -d "$MKBOOT_DIR/.git" ]]; then
  git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg "$MKBOOT_DIR"
fi
python3 "$MKBOOT_DIR/mkbootimg.py" \
  --header_version 4 \
  --kernel "$ART/${BASE}-Image" \
  --output "$ART/${BASE}-boot.img" \
  --os_version 16.0.0 \
  --os_patch_level 2026-10

# Same image with an AVB hash footer (test key). Useful if the bootloader wants
# a footer; unlocked Pixel bootloaders accept unsigned kernel images either way.
log "Create boot-avb.img (best effort)"
cp "$ART/${BASE}-boot.img" "$ART/${BASE}-boot-avb.img"
AVB_OK=0
for avb_url in \
  'https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool?format=TEXT' \
  'https://android.googlesource.com/platform/external/avb/+/refs/heads/master/avbtool.py?format=TEXT'
do
  if curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 "$avb_url" \
       | base64 -d > "$WORK/avbtool.py" 2>/dev/null; then
    AVB_OK=1
    break
  fi
done
if [[ "$AVB_OK" == "1" ]]; then
  if ! curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 \
       'https://android.googlesource.com/platform/external/avb/+/refs/heads/master/test/data/testkey_rsa2048.pem?format=TEXT' \
       | base64 -d > "$WORK/testkey_rsa2048.pem" 2>/dev/null; then
    openssl genrsa -out "$WORK/testkey_rsa2048.pem" 2048
  fi
  if python3 "$WORK/avbtool.py" add_hash_footer \
        --partition_name boot \
        --partition_size "$BOOT_PARTITION_SIZE" \
        --image "$ART/${BASE}-boot-avb.img" \
        --algorithm SHA256_RSA2048 \
        --key "$WORK/testkey_rsa2048.pem" \
        --rollback_index 0
  then
    python3 "$WORK/avbtool.py" info_image --image "$ART/${BASE}-boot-avb.img" | sed -n '1,20p'
  else
    AVB_OK=0
  fi
fi
if [[ "$AVB_OK" != "1" ]]; then
  warn "AVB footer failed; dropping ${BASE}-boot-avb.img"
  rm -f "$ART/${BASE}-boot-avb.img"
fi

log "Create AnyKernel3 zip"
AK3_DIR="$WORK/AnyKernel3"
if [[ ! -d "$AK3_DIR/.git" ]]; then
  git clone --depth=1 --single-branch -b "$AK3_REF" "$AK3_REPO" "$AK3_DIR"
fi
rm -rf "$AK3_DIR/.git"
cp "$IMAGE" "$AK3_DIR/Image"
( cd "$AK3_DIR" && zip -r9 "$ART/${BASE}-AnyKernel3.zip" . -x '*.git*' '*.zip' )

cp "$CONFIG_OUT" "$ART/${BASE}-kernel.config"
{
  echo "target=Google Pixel 8a (akita)"
  echo "kernel_repo=$KERNEL_REPO"
  echo "kernel_ref=$KERNEL_REF"
  echo "kernel_release=$KERNEL_RELEASE"
  echo "sukisu_ref=$SUKISU_REF"
  echo "sukisu_commit=$(git -C "$KERNEL_DIR/KernelSU" rev-parse HEAD)"
  echo "susfs_repo=$SUSFS_REPO"
  echo "susfs_ref=$SUSFS_REF"
  echo "susfs_commit=$(git -C "$SUSFS_DIR" rev-parse HEAD)"
  echo "susfs_version=$(grep -oE 'SUSFS_VERSION \"[^\"]+\"' "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" | head -1 | cut -d'"' -f2)"
  echo "kpm=$KPM"
  echo "clang=$(clang --version | head -n 1)"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$ART/build-info.txt"

( cd "$ART" && find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -printf '%f\n' \
    | sort | xargs -r sha256sum > SHA256SUMS.txt )

log "Done"
ls -lh "$ART"
cat "$ART/build-info.txt"
