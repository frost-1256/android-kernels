# AGENTS.md - LineageOS 23.2 / WitAqua Spacewar Kernel

> 隣の `../spacewar_mod/AGENTS.md` は NothingOSS stock (NOS 3.2) 用。ここは **LineageOS 系 ROM (WitAqua 16.2 / lineage-23.2) 用の別系統**。Snapdragon LLVM等のルールは適用しない。

## Target固定: Nothing Phone (1) Spacewar / SD778G+ / 5.4 qGKI (LineageOS lineage-23.2)

- SoC: SM7325 (lahaina系), Kernel: `msm-5.4` QGKI。ROM: WitAqua 16.2 v3.2 (Android 16, lineage-23.2由来)
- ソース: `https://github.com/LineageOS/android_kernel_nothing_sm7325` branch `lineage-23.2`
  - 基準commit: `7ed191eb55b6` (WitAqua同梱boot.imgのカーネル文字列 `5.4.302-qgki-g7ed191eb55b6` と一致)
  - ローカルブランチ: `witaqua` (素) / `witaqua-susfs` (ReSukiSU+SUSFS)
  - クローンは `--depth=1 --single-branch` (履歴が必要なら `git fetch --unshallow`)
- **ツールチェーン: AOSP clang r563880c + `LLVM=1 LLVM_IAS=1`** (Snapdragon LLVMは使わない)
  - 根拠: WitAquaカーネルのビルド文字列が `Android (14054515, +pgo, +bolt, +lto, +mlgo, based on r563880c) clang version 21.0.0`、同リポジトリ`build.config.common`の`LLVM=1`、LineageOS `BoardConfigKernel.mk`の`clang-stable` + `LLVM=1 LLVM_IAS=1`
  - DL元 (公式): `https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android16-qpr2-release/clang-r563880c.tar.gz` → `~/toolchains/clang-r563880c`
- ビルド手順 (kernel rootで):
```bash
export PATH="$HOME/toolchains/clang-r563880c/bin:$PATH"
make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 CC="ccache clang" \
  vendor/lahaina-qgki_defconfig vendor/debugfs.config [resukisu.config]
make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 CC="ccache clang" [-j$(nproc)] Image
```
  - config根拠: デバイスツリー `BoardConfig.mk` の `TARGET_KERNEL_CONFIG := vendor/lahaina-qgki_defconfig vendor/debugfs.config` / `TARGET_KERNEL_NO_GCC := true`
  - fragmentは `arch/arm64/configs/` 直下必須 (`vendor/` 下はkbuildの`%.config`探索外)
- **KMI/vermagic絶対維持**: WitAquaのvendorモジュールは `5.4.302-qgki-g7ed191eb55b6` 前提
  - `CONFIG_LOCALVERSION="-qgki"` のまま (LOCALVERSIONを上書きしない)。変更は必ずcommitして `-dirty` を避ける (setlocalversionがgit statusを見る)
  - `kernel/.scmversion` に `-g7ed191eb55b6` を固定 (ビルドスクリプトが毎回書く)。これが無いとブランチのHEAD commit hashがrelease文字列に入り (`-gd40826358578`等)、vendorモジュールがvermagic不一致でロード不能になる
  - SUSFS移植はKMI中立 (5.4では `struct kstat.mnt_id` を追加しない)
- 検証済み (2026-09-17): 素カーネルで起動・モジュール44個ロード・`unknown symbol`/`disagrees` 0件
- 検証済み SUSFS版 (2026-09-17): 起動OK・モジュール44個ロード。ReSukiSU manager v4.2.0-rc2 が「動作中 Built-in」、driver `v4.1.0-6d674e50@ReSukiSU (35144/4)`、SuSFS `v2.3.0` 表示
  - manager APK: `~/Downloads/ReSukiSU_v4.2.0-rc2_35144-arm64-v8a-release.apk` (pkg `com.resukisu.resukisu`)
- 注意: `fastboot flash boot` は「現在のslot」に書く。本機は検証中に active slot が b→a に変わったため、現在 boot_a=SUSFS版 / boot_b=素版。復旧は `fastboot flash boot stock/WitAqua-16.2-boot.img` を両slotまたはactive slotへ

## スクリプト

- `build_witaqua.sh` … 素のlineage-23.2カーネル → `build/Image`
- `build_witaqua_resukisu.sh` … ReSukiSU+SUSFS v2 → `build/Image` (+`build/Image-resukisu`)、`KSU_VERSION=35144` 必須 (manager v4.2.0-rc2系と一致)
- `repack-boot.sh [suffix]` … `stock/WitAqua-16.2-boot.img` のramdisk/vbmetaを維持しkernelのみ差替え → `WitAqua-16.2-boot-lineage23.2[-suffix].img`
- 書込み: `fastboot flash boot <img>` (端末unlock済 / 現行slot `_b` / data消去なし)。復旧は `stock/WitAqua-16.2-boot.img` を焼き戻す
- コミットはGPG署名が非対話でタイムアウトするため `git -c commit.gpgsign=false commit` を使う

## ReSukiSU + SUSFS v2.3.0 構成 (witaqua-susfs)

- KernelSU: `https://github.com/ReSukiSU/ReSukiSU` submodule @ `6d674e50` (v4.2.0-rc2-9) + `drivers/kernelsu -> ../KernelSU/kernel` symlink + `drivers/Kconfig`/`drivers/Makefile` 配線
  - ksu-sideパッチは不要 (ReSukiSU mainは必要フック `ksu_handle_stat/execveat/faccessat/sys_reboot` 内蔵)
- SUSFS: susfs4ksu `gki-android12-5.10` v2.3.0 の 5.4手移植。移植差分は `patches/kernel-side-v2.patch` (元: `../spacewar_mod/susfs-backups/v230/`)
  - `patches/` に `susfs.c` / `susfs.h` / `susfs_def.h` も保管 (kernel rootへコピーして使う)
  - 5.4手当て: `fs/proc/bootconfig.c` は存在しないため `fs/proc/cmdline.c` へspoof、`selinux_state.ss->` 化、fsnotify 5.4 API、`ksu_handle_post_execveat_sucompat` なし
  - 再適用時のreject想定: `drivers/Kconfig` / `drivers/Makefile` (nothing_thermal行の有無) / `mm/memory.c` (include位置) の3箇所のみ手当て
- fragment: `arch/arm64/configs/resukisu.config` (KSU_MANUAL_HOOK + SUSFS v2、`KSU_SUSFS_SUS_SU`と`KPM`は無効)
- パッチを当てたkernel treeで素ビルドに戻す場合は `git checkout witaqua` + 再ビルド (submoduleはそのまま)
