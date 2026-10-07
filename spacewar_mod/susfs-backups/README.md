# SUSFS configurations for Nothing Phone (1) Spacewar (msm-5.4 qGKI)

Two independent root/SUSFS configurations are kept for this kernel.
Only one can be active in the working tree at a time; use the restore
scripts to switch before building.

| | v155 (legacy) | v230 (new) |
|---|---|---|
| SukiSU | v3.1.4 (flat tree) | 4.2.0 builtin branch |
| SUSFS kernel | susfs4ksu `kernel-5.4` v1.5.5 | susfs4ksu `gki-android12-5.10` v2.3.0 (backported to 5.4) |
| driver versionCode | 12960 | 40900 |
| manager APK | SukiSU_v3.1.4_12960-release.apk | SukiSU 4.2.0 manager (40900) |
| fragment | `kernel/arch/arm64/configs/sukisu.config` | `kernel/arch/arm64/configs/sukisu-v4.config` |
| build script | `kernel/build_5.4_sukisu.sh` | `kernel/build_5.4_sukisu_v4.sh` |
| artifacts | `Spacewar-boot-sukisu.img`, `Spacewar-SukiSU-SUSFS-5.4.289.zip` | `Spacewar-boot-sukisu-v4.img`, `Spacewar-SukiSUv4-SUSFSv2-5.4.289.zip` |

## Switch

```bash
# -> legacy v1.5.5
./susfs-backups/restore-v155.sh
cd kernel && ./build_5.4_sukisu.sh

# -> new v2.3.0
./susfs-backups/restore-v230.sh
cd kernel && ./build_5.4_sukisu_v4.sh
```

`build_5.4_sukisu*.sh` uses stock clang r383902b + ARM GNU 14.2
(`CC=clang`, `CROSS_COMPILE=aarch64-none-linux-gnu-`, `CLANG_TRIPLE=aarch64-linux-gnu-`,
`LD=ld.lld`, ccache-wrapped) and `DEFCONFIG=vendor/spacewar-stock_defconfig`.

## Contents

### v155/
- `kernel-side-v155.patch` – full kernel-tree diff of the v1.5.5 integration
- `ksu-side-v155.patch` – KernelSU v3.1.4 side diff (flat tree)
- `KernelSU-v314-patched.tar.gz` – complete patched KernelSU tree
- `fs-susfs-v155.c`, `susfs.h`, `susfs_def.h` – v1.5.5 kernel-side sources
- `50_add_susfs_in_kernel-5.4.patch` – upstream v1.5.5 kernel patch

### v230/
- `kernel-side-v2.patch` – full kernel-tree diff of the v2.3.0 backport (5.4 hand-port)
- `ksu-side-v2.patch` – KernelSU builtin side diff (5.4 fixes: sulog nofault)
- `selinux_hide_stub.c` – 5.4 stub replacing the 5.10+ `feature/selinux_hide.c`
- `susfs.c`, `susfs.h`, `susfs_def.h` – v2.3.0 kernel-side sources
- `50_add.patch` – upstream `50_add_susfs_in_gki-android12-5.10.patch` (reference)

## v2.3.0 → 5.4 port notes

Kernel files hand-ported (upstream patch is written for GKI 5.10):
`fs/namei.c` (SUS_PATH + OPEN_REDIRECT incl. `do_last`/`path_openat`),
`fs/readdir.c`, `fs/stat.c`, `fs/statfs.c`, `fs/proc/task_mmu.c`, `fs/proc/cmdline.c`,
`fs/proc/fd.c`, `mm/memory.c`, `fs/exec.c`, `fs/open.c`, `security/selinux/{avc.c,hooks.c,selinuxfs.c}`.
5.4 adaptations: `struct kstat.mnt_id` added, `selinux_state.ss->status_lock`,
fsnotify `handle_event` (pre-5.9 API), `strncpy_from_user_nofault` shim,
`selinux_hide` disabled (5.10+ only), `ksu_handle_post_execveat_sucompat` removed
(builtin does not provide it).

## Third configuration: ReSukiSU (non-GKI manager)

The SukiSU 4.2.0 manager refuses non-GKI kernels ("GKI only"), so the v2 kernel can
also be paired with **ReSukiSU**, which keeps non-GKI support.

| | ReSukiSU variant |
|---|---|
| kernel driver | ReSukiSU main `6d674e50` (`KernelSU/` clone), manual-hook mode |
| manager APK | `ReSukiSU_v4.2.0-rc2_35144-arm64-v8a-release.apk` |
| driver version | 35144 (matches manager) |
| fragment | `kernel/arch/arm64/configs/resukisu.config` |
| build script | `kernel/build_5.4_resukisu.sh` |
| artifacts | `Spacewar-boot-resukisu.img`, `Spacewar-ReSukiSU-SUSFSv2-5.4.289.zip` |

The kernel-side SUSFS v2 backport is unchanged (same `kernel-side-v2.patch`); the
ReSukiSU manual hooks it requires (`ksu_handle_stat` / `ksu_handle_execveat` /
`ksu_handle_faccessat` / `ksu_handle_sys_reboot`) were already present in that patch's
call sites. The SukiSU builtin tree (with the ReSukiSU signature added) is archived at
`susfs-backups/v230/KernelSU-sukisu-v4-builtin-patched.tar.gz` and its signature patch
at `susfs-backups/v230/ksu-side-v2-resukisu-sign.patch`.

On-device result: ReSukiSU manager reports **動作中 / Working**, driver version
`v4.2.0-rc2-6d674e50@ReSukiSU (35144/4)`, SUSFS `v2.3.0`, and grants root
(`KernelSU: allow root for: 10250`).
