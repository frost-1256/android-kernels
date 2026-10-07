# Spacewar (Nothing Phone 1) 5.4 qGKI kernel — SukiSU + SUSFS

Two root/SUSFS configurations are maintained in parallel.
See `susfs-backups/README.md` for how to switch between them.

## Active configuration: v230 (SukiSU Ultra 4.2.0 + SUSFS v2.3.0, backported to 5.4)

- kernel tree: `kernel/` (msm-5.4 qGKI, `sm7325/v/mr`, 5.4.289)
- fragment: `kernel/arch/arm64/configs/sukisu-v4.config`
- build: `cd kernel && ./build_5.4_sukisu_v4.sh`
- driver versionCode: `40900` (matches SukiSU 4.2.0 manager)

## Legacy configuration: v155 (SukiSU v3.1.4 + SUSFS v1.5.5)

- fragment: `kernel/arch/arm64/configs/sukisu.config`
- build: `./susfs-backups/restore-v155.sh && cd kernel && ./build_5.4_sukisu.sh`
- driver versionCode: `12960` (manager `SukiSU_v3.1.4_12960-release.apk`)

## Artifacts

| variant | boot.img | AnyKernel3 zip |
|---|---|---|
| v230 (SukiSU 4.2.0, GKI-only manager) | `Spacewar-boot-sukisu-v4.img` | `Spacewar-SukiSUv4-SUSFSv2-5.4.289.zip` |
| v230 + ReSukiSU (non-GKI manager) | `Spacewar-boot-resukisu.img` | `Spacewar-ReSukiSU-SUSFSv2-5.4.289.zip` |
| v155 (SukiSU v3.1.4) | `Spacewar-boot-sukisu.img` | `Spacewar-SukiSU-SUSFS-5.4.289.zip` |

Regenerate artifacts from `kernel/build/Image` (stock NOS 3.2 ramdisk base):

```bash
./repack-boot.sh v4      # or: v155
```

## Flash

```bash
fastboot boot  Spacewar-boot-sukisu-v4.img   # test first
fastboot flash boot_a Spacewar-boot-sukisu-v4.img
```

## AI assistance

Developed with an AI coding agent (**opencode**, model `deepseek-v4.1-flash`):
the SUSFS v2 backport, KernelSU/ReSukiSU integration, build/repack tooling and
documentation were produced in an assisted session, then reviewed and tested on
a real device by the maintainer. Provided as-is, no warranty.

## Layout

- `kernel/` – kernel source and build scripts
- `AnyKernel3/` – flashable zip template (device=spacewar)
- `stock/` – NOS 3.2 stock boot.img used as ramdisk base
- `tools/magiskboot` – boot image unpack/repack
- `susfs-backups/` – patch series, KernelSU trees and restore scripts for both configs
- `repack-boot.sh` – build boot.img + AnyKernel3 zip from a compiled Image
- `verification/` – artifact/API checks and QEMU boot smoke tests (see `verification/README.md`)
