# AGENTS.md - Android Kernel Build Rules

> 準拠チュートリアル: https://github.com/ravindu644/Android-Kernel-Tutorials
> 原文README: https://raw.githubusercontent.com/ravindu644/Android-Kernel-Tutorials/refs/heads/main/README.md
> このリポジトリでカーネルを触るエージェントは必ず本ファイルに従うこと。

## Target固定: Nothing Phone (1) Spacewar / SD778G+ / 5.4 qGKI

- SoC: SM7325-AE (lahaina), Kernel: `msm-5.4` QGKI (GKI 1.0)。
- スクリプト固定: `build_5.4.sh` (=`build_qGKI.sh`) のみ。toolchainはSnapdragon LLVM 10.0.9 + ARM GNU 14.2、make引数は `ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-none-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu-`。`LLVM=1` に勝手に変えない。
  - Snapdragon LLVM 10.0.9の素性: https://github.com/xiangfeidexiaohuo/Snapdragon-LLVM/blob/10.0.9/README.md (llvm.org 9.0/10.0系 + QC Linker)。初回ビルドはこの構成で実施したがロゴ停止した。
  - 例外 (根拠ありの切替): stock boot.imgのIKCONFIG実測で `CC_VERSION_TEXT=r383902b clang 11.0.2` + `LD_IS_LLD=y` + ThinLTO/CFI のため、`build_5.4_stock.sh` (clang-r383902b + GNU 14.2 + `LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip`、`DEFCONFIG=vendor/spacewar-stock_defconfig`) での再ビルドを許可する。stock configは `/tmp/stockunpack/kernel-stock.config` (5.4.274, `-qgki`) を `arch/arm64/configs/vendor/spacewar-stock_defconfig` に保存した物を使う。
- ソース (優先順):
  1. 公式: `https://github.com/NothingOSS/android_kernel_msm-5.4_nothing_sm7325` branch `sm7325/v/mr` (Android 15 / NOS 3.2最新 `Spacewar-V3.2-260618-1045`, kernel 5.4.289)
  2. devicetree公式: `https://github.com/NothingOSS/android_kernel_devicetree_nothing_sm7325` branch `sm7325/v/mr` (Imageのみなら無くても可、dtb/dtbo時に必要)
  3. 実績fork: `https://github.com/ExTV/android_kernel_msm-5.4_nothing_sm7325` + devicetree `https://github.com/ExTV/android_kernel_devicetree_nothing_sm7325`
- defconfig生成必須 (stock qGKIは断片のみで完成品が無いため、初回1回だけ):
```bash
# toolchainをPATHに入れた後に kernel rootで
TARGET_BUILD_VARIANT=user NOTH_AGING_BUILD=false ./scripts/gki/generate_defconfig.sh vendor/lahaina-qgki_defconfig
# -> arch/arm64/configs/vendor/lahaina-qgki_defconfig が生成される。以後は build_5.4.sh で使う。
```
- devicetree注意 (公式README): `arch/arm64/boot/dts/vendor -> vendor/qcom/proprietary/devicetree` のsymlink、`vendor/qcom/proprietary/{camera-devicetree,display-devicetree/display,devicetree/msm-extra}` の配置・`vendor_links` を確認しないとDTS不足で失敗する。
- SETTINGS固定値:
```bash
DEFCONFIG="vendor/lahaina-qgki_defconfig"
EXTRA_CONFIGS=(vendor/debugfs.config custom.config)  # device側実績が vendor/lahaina-qgki_defconfig + vendor/debugfs.config
KERNEL_IMAGE="Image"
USE_OUT_DIR=1
MENUCONFIG=0
```
- `arch/arm64/configs/vendor/lahaina-qgki_defconfig` が無いツリーでは `ls arch/arm64/configs/vendor/*qgki* arch/arm64/configs/vendor/*lahaina*` で特定し本ファイルに追記してから進める。`build.config.msm.lahaina` のVARIANTは `qgki`。
- ccache: `build_5.4*.sh` は `ccache` があれば `CC="ccache clang"` で自動ラップ (`CCACHE_COMPRESS=1`, `CCACHE_SLOPPINESS=time_macros,...`, 上限20G)。CC変更時はkbuildが全オブジェクトを再コンパイルする点に注意。`ccache -s` でヒット率確認。

## 0. 前提・免責

- x86_64 Linux (Debian系推奨) でのみビルドする。Docker `kernel-builder` でも可。
- `make kernelversion` が通るディレクトリ = kernel root が作業起点。それ以外で `make` / スクリプトを実行しない。
- 作業前は `git status` 確認。失敗したら `git reset --hard` で戻せるようクリーンに保つ。

## 1. 依存パッケージ

- 原則手動 `apt/dnf install` は不要。`build_*.sh` が毎回不足分のみ自動導入する。
- 手動導入する場合 (Ubuntu/Debian):

```bash
sudo apt update && sudo apt install -y \
  build-essential bc bison flex patch pkg-config git curl tar xz-utils zip unzip \
  cpio rsync kmod perl python3 python-is-python3 libssl-dev libelf-dev pahole \
  libncurses-dev zlib1g-dev libyaml-dev lz4 zstd device-tree-compiler adb fastboot
```

- Fedora系は `toolchains/README` 相当の `dnf` 一式。Ubuntu 24.04+ の `libtinfo5` 不足は追わない (5.4スクリプトが `libtinfo.so.6` に向ける)。

## 2. ソース配置と kernel root判定

- Samsung: https://opensource.samsung.com/main から `Kernel.tar.gz` を取得し展開:
```bash
tar -xvf Kernel.tar.gz && rm Kernel.tar.gz
sudo chown -R "$(id -un):$(id -gn)" "/path/to/extracted/kernel/" && chmod -R u+rwX "/path/to/extracted/kernel/"
```
- その他OEM: OEM公式GitHubから取得。
- kernel root判定: `arch/` `drivers/` `Makefile` 等があり `make kernelversion` で `5.15.123` のように出る所。
  - GKI伝統: `common/` 配下。Samsung QC GKIは `common` を使う (`msm-kernel` 禁止)。Samsung MTK GKIは `kernel-5.15` 等。
- GKI区分: pre-GKI=3.10-4.19 / GKI1.0=5.4 / GKI2.0=5.10,5.15,6.1,6.6。

## 3. コンパイラ選択 (手動DL禁止)

- `make kernelversion` の `VERSION.PATCHLEVEL` のみ見る。対応表:

| kernel | script | toolchain (自動DL先 `~/toolchains`) |
|---|---|---|
| 4.9 | `build_4.9.sh` | Proton Clang 12 + Linaro GCC 7.5 |
| 4.14 OEM/stock | `build_4.14.sh` | clang-r383902b + ARM GNU 14.2 |
| 4.14 AOSP/Lineage | `build_4.14_aosp.sh` | Neutron Clangのみ `LLVM=1` |
| 4.19 | `build_4.19.sh` | clang-r353983c + ARM GNU 14.2 |
| 5.4 qGKI | `build_5.4.sh`=`build_qGKI.sh` | Snapdragon LLVM + ARM GNU 14.2 |
| 5.10 | `build_5.10.sh` | clang-r416183b のみ `LLVM=1 LLVM_IAS=1` |
| 5.15 | `build_5.15.sh` | clang-r450784e のみ `LLVM=1 LLVM_IAS=1` |
| 6.1+ | `build_6.1.sh` | clang-r510928 のみ `LLVM=1 LLVM_IAS=1` |

- 法則: stock 4.9-5.4=Clang+GCC (`CC=clang CROSS_COMPILE=... CLANG_TRIPLE=...`)、AOSP/Lineageと5.10以降=Clangのみ (`ARCH=arm64 LLVM=1 LLVM_IAS=1`)。詳細は `toolchains/README.md`。
- MediaTekは `KERNEL_IMAGE="Image.gz"` (raw `Image`で起動不可が多い)。

## 4. ビルド方法 (Method 2優先)

1. 上表の `build_*.sh` を https://github.com/ravindu644/Android-Kernel-Tutorials/tree/main/build_scripts から取り kernel root直下 (Makefile横) に置く。
2. 先頭SETTINGSのみ編集:
```bash
DEFCONFIG="gki_defconfig"      # arch/arm64/configs配下。vendor内なら vendor/foo_defconfig
EXTRA_CONFIGS=()               # 例 (custom.config ksu.config)
KERNEL_IMAGE="Image"           # Image | Image.gz | Image.gz-dtb
USE_OUT_DIR=1                  # Samsung Exynosは0 (in-tree)
MENUCONFIG=0                   # エージェント非対話実行は必ず0。対話確認時のみ1
export KBUILD_BUILD_USER="..."
# export TARGET_SOC=s5e9925 PLATFORM_VERSION=12 ANDROID_MAJOR_VERSION=s  # Samsung README_Kernel.txt指定時のみ
```
3. Makefileに `REAL_CC`/`CFP_CC` や python wrapper行があれば除去 (`patches/004.remove_gcc wrapper.patch`参照)。
4. 実行:
```bash
chmod +x build_xxxx.sh
./build_xxxx.sh
```
- 動作: deps補完→`~/toolchains`にDL(中断時は再実行でクリーン再開)→`DEFCONFIG+EXTRA_CONFIGS`で`.config`生成→compile→`build/`にコピー。原本は `out/arch/arm64/boot/` (`USE_OUT_DIR=0`なら `arch/arm64/boot/`)。
- Method 1 (素のmake理解用) はチュートリアル§05参照。エージェントは原則使わない。使う場合もPATH先頭にtoolchain `bin` を `export PATH=...:$PATH` し `clang -v` 確認。

## 5. カスタマイズ

- Temporary: `MENUCONFIG=1` で開くmenuconfig変更は `.config` (`out/`直下 or root直下) のみで再実行で消える。恒常化しない。
- Permanent (必須手順): `arch/arm64/configs/custom.config` を作り `CONFIG_XXX=y/n` を追記→`EXTRA_CONFIGS=(custom.config)`。menuconfigで `Shift+?` 左上の `CONFIG_`名を転記する。
- 注意: fragmentは `arch/arm64/configs/` 直下に置くこと (`vendor/` 下はkbuildの `%.config` ルールが探索しないため `No configuration exists` で失敗する)。
- SukiSU+SUSFS (Spacewar実績, 5.4非GKI): SukiSU-Ultra は `builtin`/最新mainではなく **tag `v3.1.4`** + susfs4ksu **`kernel-5.4` (v1.5.5)** の組合せ。手順: `curl -LSs .../setup.sh | bash -s v3.1.4` で `KernelSU/` + `drivers/kernelsu` symlink 作成 → susfs4ksu から `fs/susfs.c`, `include/linux/susfs{,_def}.h`, `50_add_susfs_in_kernel-5.4.patch` を配置・適用 (`fs/proc/bootconfig.c` は5.4に無いのでskipし `fs/proc/cmdline.c` へspoofを手当て、`fd.c`/`task_mmu.c`/`mount.h` のrejectも手当て) → `10_enable_susfs_for_ksu.patch` + `sucompat.h` を `KernelSU/` へ適用し reject (`Makefile`/`core_hook.c`/`ksud.c`) は手当て。
- 5.4固有の必須手当て (v3.1.4は5.7+/5.9+/5.10+前提のため): `sepolicy.c add_filename_trans` に<5.7分岐追加、`rules.c get_policydb` を `selinux_state.ss->policydb` に、`kernel_compat.c` に `strncpy_from_user_nofault` backport追加、`CONFIG_KSU_SUSFS_SUS_SU` は無効化 (kprobe変数未定義でビルド不可、susfs4ksu README既知の問題)。
- fragmentは `arch/arm64/configs/sukisu.config`、ビルドは `build_5.4_sukisu.sh` (stock clang + `EXTRA_CONFIGS=(sukisu.config)`)。成果物: `Spacewar-boot-sukisu.img` / `Spacewar-SukiSU-SUSFS-5.4.289.zip` (AnyKernel3)。
- バージョン整合必須: KernelSU/kernel/Makefile は `git rev-list --count main` で版数を計算するためtag `v3.1.4`でも最新値(14343)になりmanagerと不一致になる。`KSU_VERSION=12960` (v3.1.4正規値) を make引数で上書きすること。managerは `SukiSU_v3.1.4_12960-release.apk` (https://github.com/SukiSU-Ultra/SukiSU-Ultra/releases/download/v3.1.4/SukiSU_v3.1.4_12960-release.apk) を使う。
- SUSFS v2.x バックポート (SukiSU 4.2.0 builtin + susfs4ksu v2.3.0): `KernelSU/` を `builtin` branchにし、susfs4ksu `gki-android12-5.10` の `fs/susfs.c`/`include/linux/susfs{,_def}.h`/`50_add_susfs_in_gki-android12-5.10.patch` を5.4へ手移植。5.4固有手当て: namei/readdir/statfs/task_mmu/exec/open/stat/selinux周り、`selinux_state.ss->status_lock`化、`fsnotify_ops.handle_event`化、`sdcard monitor`はfsnotify 5.4 API、`strncpy_from_user_nofault`はKSU側inlineを使用、KSU `selinux_hide` は5.10+限定のため `feature/selinux_hide_stub.c` で無効化、`ksu_handle_post_execveat_sucompat` は builtin に無いため exec.c から除去。fragment `sukisu-v4.config`、ビルド `build_5.4_sukisu_v4.sh` (`KSU_VERSION=40900` = manager 4.2.0 と一致)。成果物: `Spacewar-boot-sukisu-v4.img` / `Spacewar-SukiSUv4-SUSFSv2-5.4.289.zip`。
- ReSukiSU (非GKIマネージャー) 変種: SukiSU 4.2.0マネージャーは非GKIを拒否するため、`KernelSU/` を ReSukiSU main (`6d674e50`) のクローンに差替え、`resukisu.config` (KSU_MANUAL_HOOK + SUSFS v2) と `build_5.4_resukisu.sh` (`KSU_VERSION=35144`) でビルド。SUSFS v2カーネル側は無変更 (必要フック ksu_handle_stat/execveat/faccessat/sys_reboot は既存)。成果物 `Spacewar-boot-resukisu.img` / `Spacewar-ReSukiSU-SUSFSv2-5.4.289.zip`。実機でマネージャー「動作中」・driver 35144一致・SUSFS v2.3.0・root付与を確認。SukiSU builtinツリーは `susfs-backups/v230/KernelSU-sukisu-v4-builtin-patched.tar.gz` に退避。
- KMI維持 (v2): `struct kstat.mnt_id` は5.4ではuapiに `STATX_MNT_ID` が無くユーザー空間に出ない死にフィールドのため追加しない (`include/linux/stat.h` 無変更)。`fs/stat.c` のmnt_id代入は `>=5.10` ガード。`CONFIG_MODVERSIONS=y` のため、これでSUSFS/KSU変更によるモジュールCRC影響ゼロ (両構成ともKMI中立)。
- 手動mergeと同等: `make ARCH=arm64 LLVM=1 your_defconfig custom.config`。

## 6. Samsung / 追加パッチ

- Samsung RKP除去は `samsung-rkp/` 手順に従う (別ページ)。
- `patch -p1 < file.patch` はkernel rootで。理解のため手当て推奨:
  - `010.Disable-CRC-Checks.patch`: venモジュール`*.ko`が載らない最終手段。ABI破壊・panicの危険。rebuild可能な物はrebuild優先。
  - `011.stock_defconfig.patch`: `stock_defconfig`複製後に適用。`There is an internal problem` 対策。
  - `012/013.force-selinux-permissive`: デバッグのみ。出荷物に残さない。
  - `016.KernelSU-Hooks.patch`: KernelSU hooks付与。
  - `017.nuke_dirty_string.patch`: `-dirty`除去。
- ビルドエラーは先に `patches/README.md` (Werror無効化`009`、yylloc`018`、secclass`019`等) を当たる。

## 7. 成果物とboot.imgリパック (magiskboot)

- 成果物生成は `./repack-boot.sh {v4|v155}` を使う (`kernel/build/Image` + `stock/Spacewar_V3.2_stock_boot.img` → boot.img + AnyKernel3 zip)。magiskbootは `tools/magiskboot` 同梱。**repackはコンポーネントのあるディレクトリで実行**しないと空イメージになる点に注意 (スクリプトは一時ディレクトリで実施)。
- `.ko` を含む構成では `vendor_boot`/`vendor_dlkm` 側も更新が必要 (`special-tools/` 参照)。
- 手動手順:
```bash
mv libmagiskboot.so magiskboot && chmod +x magiskboot && sudo cp magiskboot /usr/local/bin/
magiskboot unpack boot.img
# build/Image を unpack先にコピーし kernel を置換 (元boot.imgは消さない)
magiskboot repack boot.img  # -> new-boot.img を boot.imgに改名
```
- Samsung: `AP_*.tar.md5`→`.tar`改名→展開→`boot.img.lz4`を `lz4 boot.img.lz4`。Odin用は `tar -cvf Custom-Kernel.tar boot.img` しAPスロットで焼く。fastboot機は `fastboot flash boot boot.img`。

## 8. エージェント運用ルール

- kernel root外でビルドコマンドを打たない。`[ -f Makefile ] && [ -d arch/arm64 ]` を確認。
- toolchainを直DL/別Clangに勝手に変えない。変えるなら `toolchains/` の実績表記と起動確認を根拠に示す。
- `MENUCONFIG=1` のまま放置しない。CI/非対話は `MENUCONFIG=0`。
- `.config`/`out/`/`build/` を手で消さずスクリプトに任せる。`warning: ignoring unsupported character` は無視可。
- 変更は `custom.config` + patch適用記録として残し、安易にdefconfig直書きしない。
