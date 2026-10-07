# Verification

## 1. Artifact integrity

| check | result |
|---|---|
| `Spacewar-boot-sukisu-v4.img` header | v3, KERNEL_SZ 40442368, RAMDISK_SZ 9001543 (= stock NOS 3.2 ramdisk) |
| embedded config | `Linux/arm64 5.4.289`, all `CONFIG_KSU_SUSFS_*` of `sukisu-v4.config` present |
| SUSFS version string in kernel | `susfs is initialized! version: v2.3.0` |
| SukiSU version string | `v4.2.0-b20dee70@builtin` (driver versionCode 40900) |
| v2-only API symbols in vmlinux | `susfs_add_sus_map`, `susfs_set_avc_log_spoofing`, `susfs_get_enabled_features`, `susfs_start_sdcard_monitor_fn`, `susfs_open_redirect_spoof_do_proc_readlink` present; v1-only `susfs_sus_ino_for_filldir64`/`..._generic_fillattr` absent |
| arm64 Image header | `code0=0x91005a4d`, `text_offset=0x80000`, `flags=0xa`, magic `ARMd` — identical to the stock NOS 3.2 kernel header |
| vmlinux ELF | ELF64, Machine AArch64, entry `0xFFFFFFC010080000` |
| AnyKernel3 zip | `Image` SHA256 equals `kernel/build/Image`; `anykernel.sh` device `spacewar`, `BLOCK=boot` |
| ramdisk | byte-identical to the stock NOS 3.2 ramdisk (sha256 `d376b62b…`, 21,710,080 bytes) |
| legacy v1.5.5 artifact | `Spacewar-boot-sukisu.img` contains `susfs is initialized! version: v1.5.5` |

## 2. Reproducibility

- `susfs-backups/v230/kernel-side-v2.patch` sha256 == current `kernel/` `git diff` sha256
  (`539dc247fc3ede39118201a1342be03865fb807f1ebd668a687c2709604dc338`).
- `susfs-backups/v155/kernel-side-v155.patch` sha256 == `git diff` after
  `susfs-backups/restore-v155.sh` (`e5f037f2d971b8429a18c85ec12d03f452b7f3e0b4466bcd1fdc6fa53b3aee12`),
  i.e. the same source state as the device-booted v1.5.5 build.
- `repack-boot.sh` regenerates both boot.img and AnyKernel3 zip from `kernel/build/Image`
  and the stock base at `stock/Spacewar_V3.2_stock_boot.img`.

## 3. QEMU boot smoke test

The kernel Image boots on a generic arm64 platform up to the point where Qualcomm
SCM firmware is required (QEMU `virt` has none), identically to the stock kernel.

```
qemu-system-aarch64 -M virt -cpu cortex-a57 -smp 4 -m 2048 \
  -kernel kernel/build/Image \
  -append "console=ttyAMA0 earlycon=pl011,0x9000000 loglevel=7" \
  -nographic -no-reboot
```

- `qemu-boot-v4.log` – built kernel: reaches `scm_mem_protection_init` ->
  `qcom_scm_call_smccc` -> `do_undefinstr` -> panic. Console shows
  `Linux version 5.4.289-qgki-g1d557de4d904-dirty`, memory/RCU/IRQ/timer init all complete.
- `qemu-boot-v155.log` – legacy SukiSU v3.1.4 + SUSFS v1.5.5 kernel (the build whose
  Image was flashed on the device): same boot path, same panic point.
- `qemu-boot-stock.log` – stock NOS 3.2 kernel (5.4.274) panics at the exact same
  code path, proving the failure is a QEMU platform limitation (no Qualcomm firmware),
  not a regression from the SUSFS v2 / SukiSU 4.2.0 backport.

All three kernels reach the same initcall stage; early boot is unaffected by the backport.

Final boot confirmation still requires flashing on the device
(`fastboot boot Spacewar-boot-sukisu-v4.img`).

## 4. KMI / module-CRC audit

`CONFIG_MODVERSIONS=y` (stock config), so vendor modules check symbol CRCs on load.

The first cut of the v2 port added `struct kstat.mnt_id` (as in the GKI 5.10 source),
which would change the genksyms CRC of exported symbols taking `struct kstat *`.
Audit against the 309 vendor modules in
`~/Spacewar_V3.2-250926-1631/vendor/lib/modules/5.4-gki/` (`modprobe --dump-modversions`):

| exported symbol | importing modules |
|---|---|
| `vfs_getattr` | 1 (`incrementalfs.ko`) |
| `vfs_getattr_nosec` | 0 |
| `generic_fillattr` | 0 |
| `vfs_statx`, `vfs_statx_fd`, `vfs_fstatat` | 0 |

On this 5.4 tree `STATX_MNT_ID` does not exist (`include/uapi/linux/stat.h` and
`cp_statx` never export `stx_mnt_id`), and `fs/susfs.c` already guards its
`stat->mnt_id` write with `>= 5.10`. The field was therefore **dead on 5.4** and only
added KMI risk, so it was removed:

- `include/linux/stat.h` is unmodified (`git diff` empty) — `struct kstat` keeps the
  stock layout, so no module CRC is affected by the SUSFS/KSU work.
- `fs/stat.c` keeps the SUS-KSTAT marker logic (`STATX_SUS_KSTAT[_FUSE]` result-mask
  bits) and the mnt_id writes are guarded with `#if LINUX_VERSION_CODE >= 5.10`.

The v1.5.5 variant uses `ANDROID_KABI_USE()` reserves in `vfsmount`/`task_struct` and
does not touch `struct kstat` either, so both variants are KMI-neutral.

KMI-neutrality proof for the v2 patch: `git diff --name-only` contains **no** file under
`include/`, `arch/`, `security/selinux/include/` or `scripts/`, and the patch adds no
`EXPORT_SYMBOL` — the only new headers are the additive `include/linux/susfs{,_def}.h`.
Since no existing type definition or exported prototype changes, the genksyms CRCs of
all exported symbols are identical to a stock build with the same config.

## 5. On-device test (2026-09-17, Nothing Phone 1 / slot b)

`Spacewar-boot-sukisu-v4.img` was flashed to `boot_b` on the real device
(firmware `V3.2-250926-1631`, Android 15) and booted.

| check | result |
|---|---|
| kernel | `uname -a` -> `5.4.289-qgki-g1d557de4d904-dirty #10` (the v2 build) |
| running config | `/proc/config.gz` -> `CONFIG_KSU_SUSFS_SUS_PATH=y`, `..._OPEN_REDIRECT=y`, `..._SUS_MAP=y` |
| SUSFS v2 init | dmesg: `susfs: [0][1][susfs_init] susfs is initialized! version: v2.3.0` |
| SukiSU 4.2.0 manager | installed (versionCode 40900), runs, queries v2 API successfully in logcat: `Susfs { command: Version }`, `Susfs { command: Status }`, `Susfs { command: Config { command: Get { key: "uname_value" } } }` |
| KSU supercall | `ksu fd installed`, ioctl command table logged; only KPM (`0xc0004bc8`) and feature id 4 (`selinux_hide`) are unsupported, both intentionally disabled in this 5.4 port |
| root `su` | not available: manager reports `対応`/非対応 and "KernelSU currently supports only GKI kernels", so it does not deploy `/system/bin/su` |

Conclusion: the kernel-side v2 backport is functional on the device (SUSFS v2.3.0
initialised and answering the v4 manager). Root/module management, however, is refused
by the SukiSU 4.2.0 manager because upstream SukiSU dropped non-GKI support - a
userspace limitation, not a kernel defect. For managed root on this 5.4 device use the
v155 combo (SukiSU v3.1.4 manager + driver), or a non-GKI-capable manager.

## 6. ReSukiSU (non-GKI manager) on-device result

The SukiSU 4.2.0 manager refuses non-GKI kernels, so the same v2 kernel was rebuilt
with the **ReSukiSU** driver (`KernelSU/` = ReSukiSU main `6d674e50`, manual-hook mode)
and flashed to `boot_b` (`Spacewar-boot-resukisu.img`, boot SHA1 1441048a).

Evidence (ReSukiSU v4.2.0-rc2 manager 35144):

- manager shows **動作中 / Working**, "Built-in", `SuperUser: 2, Modules: 1`
- `SuSFS バージョン v2.3.0`
- `マネージャー バージョン v4.2.0-rc2 (35144/4)`
- `Kernel driver version v4.2.0-rc2-6d674e50@ReSukiSU (35144/4)`
- kernel log: `KernelSU: allow root for: 10250` (manager UID), `ksu fd installed`
- Kernel Flasher reports Slot B boot SHA1 `1441048a`, matching the flashed image

`adb shell su` is not available because KSU sucompat targets app processes (uid >= 10000);
app-level root is managed through the manager's superuser list. The kernel-side SUSFS v2
backport is unchanged from the SukiSU build.
