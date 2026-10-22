#!/usr/bin/env bash
# Build the Linux mainline kernel + spacewar DTB for Android 17 userspace.
#
# Local:   ./spacewar_mainline/build.sh
# CI:      called by .github/workflows/build-spacewar-mainline.yml
#
# Environment:
#   KERNEL_VERSION   mainline release to fetch from kernel.org (default: 7.3)
#   KDIR             existing kernel source tree (skips download)
#   BUILD            out-of-tree build dir (default: spacewar_mainline/build/$KVER)
#   JOBS             parallel make jobs (default: nproc)
#   STOCK_BOOT_URL          optional URL of a LineageOS 24 boot.img; when set
#                           the script repacks it with the mainline Image
#   STOCK_VENDOR_BOOT_URL   optional URL of the matching vendor_boot.img; when
#                           set the script replaces its base DTB with the
#                           mainline tree and emits an empty dtbo.img
#   CMDLINE          mainline-specific cmdline baked into the repacked boot
#                    image (the stock vendor_cmdline is kept in vendor_boot)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KVER="${KERNEL_VERSION:-7.3}"
KMAJOR="${KVER%%.*}"
KDIR="${KDIR:-$ROOT/spacewar_mainline/linux-$KVER}"
BUILD="${BUILD:-$ROOT/spacewar_mainline/build/$KVER}"
ART="$ROOT/spacewar_mainline/artifacts"
DL="$ROOT/spacewar_mainline/downloads/linux-$KVER.tar.xz"
JOBS="${JOBS:-$(nproc)}"
TOOLS="$ROOT/spacewar_mainline/tools"

# The stock vendor_cmdline already carries hardware/memcg/loop/usbcontroller;
# only add the mainline-specific bits here (cmdline = boot + vendor_cmdline).
# Keep SELinux permissive for the first bring-up: the vendor policy has no
# rules for mainline device paths yet.
CMDLINE="${CMDLINE:-console=ttyMSM0,115200n8 androidboot.selinux=permissive}"

mkdir -p "$ART" "$BUILD" "$(dirname "$DL")"

if [ ! -d "$KDIR" ]; then
	echo "[1/5] fetching linux-$KVER"
	if [ ! -f "$DL" ]; then
		curl -fL --retry 3 --retry-delay 2 -o "$DL.part" \
			"https://cdn.kernel.org/pub/linux/kernel/v${KMAJOR}.x/linux-${KVER}.tar.xz"
		mv "$DL.part" "$DL"
	fi
	tar -C "$ROOT/spacewar_mainline" -xf "$DL"
fi

# Keep board-specific fixups in the repo; CI always builds a fresh tarball.
for p in "$ROOT"/spacewar_mainline/patches/*.patch; do
	[ -e "$p" ] || continue
	if patch -p1 -d "$KDIR" --dry-run -N -r - -i "$p" >/dev/null 2>&1; then
		patch -p1 -d "$KDIR" -N -r - -i "$p"
	else
		echo "patch already applied: $(basename "$p")"
	fi
done

echo "[2/5] configuring"
MAKE=(make -C "$KDIR" O="$BUILD" ARCH=arm64 LLVM=1)
# LLVM=1 sets HOSTCC=clang.  A local nix shell without glibc headers needs
# HOSTCC to be passed on the command line (environment variables are
# overridden by the kbuild assignment).
[ -n "${HOSTCC:-}" ] && MAKE+=("HOSTCC=$HOSTCC")
"${MAKE[@]}" defconfig
KCONFIG_CONFIG="$BUILD/.config" sh "$KDIR/scripts/kconfig/merge_config.sh" \
	-m -O "$BUILD" "$BUILD/.config" \
	"$ROOT/spacewar_mainline/android.fragment" \
	"$ROOT/spacewar_mainline/spacewar.fragment"
"${MAKE[@]}" olddefconfig
# merge_config -m leaves both the old and the new line for choice/tristate
# symbols; the first pass canonicalises the file, the second one resolves the
# choice (without it e.g. DRM_MSM stays =m and make Image never builds it).
"${MAKE[@]}" olddefconfig

# Hard-fail if the Android contract was silently dropped (unmet dependency,
# symbol renamed upstream, ...).  A kernel that boots but has no binderfs is
# useless here.
for sym in ANDROID_BINDERFS ANDROID_BINDER_IPC DMABUF_HEAPS_SYSTEM SECURITY_SELINUX \
	SECCOMP_FILTER DRM_MSM DRM_MSM_DSI DRM_PANEL_VISIONOX_RM692E5 SCSI_UFS_QCOM ATH11K_AHB; do
	if ! grep -qx "CONFIG_${sym}=y" "$BUILD/.config"; then
		echo "error: CONFIG_${sym}=y missing from $BUILD/.config" >&2
		grep -E "^(CONFIG_${sym}=|# CONFIG_${sym} is not set)" "$BUILD/.config" >&2 || true
		exit 1
	fi
done

echo "[3/5] building Image + DTB (-j$JOBS)"
"${MAKE[@]}" -j"$JOBS" Image qcom/sm7325-nothing-spacewar.dtb

echo "[4/5] collecting artifacts"
cp "$BUILD/arch/arm64/boot/Image" "$ART/Image"
cp "$BUILD/arch/arm64/boot/dts/qcom/sm7325-nothing-spacewar.dtb" "$ART/"
cp "$BUILD/.config" "$ART/config"
cp "$BUILD/System.map" "$ART/" 2>/dev/null || true

# Android boot header v3 keeps the base DTB in vendor_boot.img; the stock
# dtbo.img entries are overlays (fragment@N + __fixups__) applied on top of
# the generic Yupik tree from vendor_boot.  Our mainline tree is a complete
# DTB, so it replaces the vendor_boot base (see the STOCK_VENDOR_BOOT_URL
# branch below) and the dtbo must be emptied, otherwise ABL would try to
# apply the vendor overlays to a foreign tree.  pack_dtbo.py keeps the stock
# table layout (32 byte header, 32 byte entries, first DTB at offset 1024,
# padded to the partition size); the upstream mkbootimg repo ships no
# mkdtboimg.py.
rm -f "$ART/dtbo.img"
python3 "$ROOT/spacewar_mainline/tools/pack_dtbo.py" create "$ART/dtbo.img"
{
	echo "kernel: linux-$KVER"
	echo "defconfig + android.fragment + spacewar.fragment"
	echo "compiler: $(clang --version | head -1)"
	echo "boot cmdline: $CMDLINE"
	echo "dtbo: empty table (count=0; stock overlays must not be applied)"
	echo "vendor_boot: mainline DTB as base tree with qcom,msm-id=<0x1db 0x10000 0x203 0x10000> qcom,board-id=<0x1000b 0x00>"
	echo "usb: UDC a600000.dwc3 (node renamed in kodiak.dtsi)"
} > "$ART/build-info.txt"

if [ -n "${STOCK_BOOT_URL:-}" ] || [ -n "${STOCK_VENDOR_BOOT_URL:-}" ]; then
	echo "[5/5] repacking Android images"
	if [ ! -d "$TOOLS/mkbootimg" ]; then
		git clone --depth 1 \
			https://android.googlesource.com/platform/system/tools/mkbootimg \
			"$TOOLS/mkbootimg"
	fi
fi

if [ -n "${STOCK_BOOT_URL:-}" ]; then
	echo "[5/5] repacking boot.img"
	curl -fL --retry 3 -o "$BUILD/stock-boot.img" "$STOCK_BOOT_URL"
	rm -rf "$BUILD/stock-boot"
	# Keep header version, os version/patch level and the stock ramdisk; the
	# boot header v3 has no DTB field.
	mapfile -d '' -t BARGV < <(python3 "$TOOLS/mkbootimg/unpack_bootimg.py" \
		--boot_img "$BUILD/stock-boot.img" --out "$BUILD/stock-boot" \
		--format mkbootimg -0)
	python3 "$TOOLS/mkbootimg/mkbootimg.py" "${BARGV[@]}" \
		--kernel "$ART/Image" \
		--cmdline "$CMDLINE" \
		--output "$ART/boot.img"
	echo "boot.img: $(du -h "$ART/boot.img" | cut -f1)"
fi

if [ -n "${STOCK_VENDOR_BOOT_URL:-}" ]; then
	echo "[5/5] repacking vendor_boot.img (mainline base DTB)"
	curl -fL --retry 3 -o "$BUILD/stock-vendor-boot.img" "$STOCK_VENDOR_BOOT_URL"
	rm -rf "$BUILD/stock-vendor-boot"
	# Reuse every stock header field (base addresses, vendor_cmdline, vendor
	# ramdisk) and only swap the base device tree.
	mapfile -d '' -t VARGV < <(python3 "$TOOLS/mkbootimg/unpack_bootimg.py" \
		--boot_img "$BUILD/stock-vendor-boot.img" \
		--out "$BUILD/stock-vendor-boot" --format mkbootimg -0)
	python3 "$TOOLS/mkbootimg/mkbootimg.py" "${VARGV[@]}" \
		--dtb "$ART/sm7325-nothing-spacewar.dtb" \
		--vendor_boot "$ART/vendor_boot.img"
	echo "vendor_boot.img: $(du -h "$ART/vendor_boot.img" | cut -f1)"
fi

if [ -z "${STOCK_BOOT_URL:-}" ] || [ -z "${STOCK_VENDOR_BOOT_URL:-}" ]; then
	echo "[5/5] STOCK_BOOT_URL and/or STOCK_VENDOR_BOOT_URL unset:"
	echo "      no complete flashable set (need boot.img + vendor_boot.img + dtbo.img)"
fi

echo
ls -lh "$ART"
sha256sum "$ART"/* 2>/dev/null || true
