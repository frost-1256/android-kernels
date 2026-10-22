# Nothing Phone (1) mainline (Linux 7.3 + Android 17 userspace)

`spacewar` (Nothing Phone (1), SM7325 / yupik) を、stock の 5.4 qGKI vendor
kernel ではなく Linux mainline 7.3 で動かすためのビルド一式。userspace と
vendor blobs は LineageOS 24 (Android 17) のものをそのまま使う。GKI/KMI の
互換性は追わない（vendor module は mainline ではロードできない前提）。

## 1. 重要な設計判断: DTB は vendor_boot に入れる

stock ROM をダンプして確認した結果、**dtbo の entry は完全な DTB ではなく
overlay** だった。

- `dtbo.img` entry 28/29 は `fragment@N` と `__fixups__` を持つ overlay で、
  root には `model` / `qcom,msm-id` / `qcom,board-id` しかない。
- overlay の base tree は `vendor_boot.img` の `dtb` セクションにある
  "Qualcomm Technologies, Inc. Yupik SoC"（`qcom,msm-id = <0x1db 0x10000
  0x203 0x10000>`, `qcom,board-id = <0>`）。stock では ABL がこの base を
  選び、`dtbo` の overlay を適用して spacewar の panel/touch を足す。
- `boot.img` (header v3) に DTB は無い。

したがって mainline の完全な DTB を `dtbo` の overlay として置いても適用
されない。**mainline DTB は `vendor_boot.img` の base DTB と差し替え、
`dtbo.img` は空 (entry count = 0) にする**。stock overlay を mainline tree に
適用すると失敗するため、dtbo は必ず空にする。

DTS 側には stock と同じ `qcom,msm-id` / `qcom,board-id` を入れてある
(`patches/0001-spacewar-abl-dtbo-ids.patch`)。これで ABL が mainline base を
選択できる。

## 2. ビルド

### GitHub Actions（正）

`.github/workflows/build-spacewar-mainline.yml` を `workflow_dispatch` で実行する。

| input | 既定値 | 意味 |
|---|---|---|
| `kernel_version` | `7.3` | kernel.org のバージョン |
| `stock_boot_url` | 空 | LineageOS 24 の `boot.img` URL（boot.img を作る場合） |
| `stock_vendor_boot_url` | 空 | 同じ ROM の `vendor_boot.img` URL（mainline DTB を入れる場合） |
| `cmdline` | `console=ttyMSM0,115200n8 androidboot.selinux=permissive` | boot.img の cmdline |
| `make_release` | `false` | GitHub Release に成果物を添付 |

`stock_*_url` は runner から到達できる URL（公開 URL か、Release asset など）
であること。flash 可能な一式を作るには **両方** 必要。

### ローカル

カーネルツリーは git 管理外。初回は tarball を取得して展開する。

```sh
cd /home/spring/android-kernels
nix shell nixpkgs#llvmPackages.clang-unwrapped nixpkgs#llvm nixpkgs#lld \
  nixpkgs#gcc nixpkgs#gnumake nixpkgs#flex nixpkgs#bison nixpkgs#bc \
  nixpkgs#perl nixpkgs#elfutils nixpkgs#openssl nixpkgs#openssl.bin \
  nixpkgs#lz4 nixpkgs#zstd nixpkgs#cpio nixpkgs#python3 nixpkgs#patch \
  nixpkgs#curl --command bash -c '
  export LD_LIBRARY_PATH='"$(nix eval --raw nixpkgs#openssl.out)"'/lib:$LD_LIBRARY_PATH
  export HOSTCC=/tmp/hostcc-ssl   # gcc -I<openssl.dev>/include -L<openssl.out>/lib
  export STOCK_BOOT_URL=file:///home/spring/android-kernels/lineage24_spacewar/boot.img
  export STOCK_VENDOR_BOOT_URL=file:///home/spring/android-kernels/lineage24_spacewar/vendor_boot.img
  bash spacewar_mainline/build.sh'
```

- `HOSTCC` は `LLVM=1` が `HOSTCC=clang` を強制するため、make の
  コマンドライン引数として渡す必要がある（`build.sh` が環境変数を
  `HOSTCC=` として渡す）。
- `certs/extract-cert` が OpenSSL を要求する。CI は `libssl-dev` で足りる。
- `kernel_version` は `KERNEL_VERSION`、出力先は `BUILD`、並列数は `JOBS`
  で変更できる。

### config

`arm64 defconfig` に `android.fragment` と `spacewar.fragment` を
`merge_config.sh -m` でマージし、`olddefconfig` を **2 回** 実行する
(2 回目がないと choice 系が解決されず `DRM_MSM=m` のままになる)。
`build.sh` は Android に必須の symbol が `=y` でない場合に失敗する
(`ANDROID_BINDERFS`, `SECURITY_SELINUX`, `DRM_MSM`, `SCSI_UFS_QCOM`,
`ATH11K_AHB` など)。

## 3. 成果物

`spacewar_mainline/artifacts/` に出力される。

| file | 内容 |
|---|---|
| `Image` | mainline kernel (arm64, 非圧縮) |
| `sm7325-nothing-spacewar.dtb` | spacewar の mainline device tree |
| `config` | 最終 `.config` |
| `System.map` | kernel symbol map |
| `build-info.txt` | version, cmdline, DTB ID などのメモ |
| `boot.img` | mainline `Image` + stock boot ramdisk (URL 指定時) |
| `vendor_boot.img` | stock vendor ramdisk + mainline base DTB (URL 指定時) |
| `dtbo.img` | 空の DTBO table (entry count = 0, 25,165,824 B に pad) |

`build.sh` は DTB ターゲットを `qcom/sm7325-nothing-spacewar.dtb` として
ビルドする (`arch/arm64/boot/dts/qcom/...` を渡すとパスが二重になる)。

## 4. 書き込み

**必ず bootloader unlock 済みで、stock の `boot.img` / `vendor_boot.img` /
`dtbo.img` / `vbmeta*.img` をバックアップしておくこと。**

Virtual A/B 端末なので slot を明示する。現在の slot は
`fastboot getvar current-slot` で確認する（以下 `$SLOT` は `a` または `b`）。

```sh
# AVB を無効化（stock ROM の vbmeta を使う）
fastboot --disable-verity --disable-verification flash vbmeta_$SLOT vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_system_$SLOT vbmeta_system.img

# mainline 一式
fastboot flash boot_$SLOT        boot.img
fastboot flash vendor_boot_$SLOT vendor_boot.img
fastboot flash dtbo_$SLOT        dtbo.img

fastboot reboot
```

- `dtbo.img` が空なのは意図的。stock dtbo の overlay を消さないと mainline
  tree に vendor overlay が適用されて壊れる。
- stock に戻すときは、バックアップした 4 イメージを同じ slot に書き戻す。
- first boot は `console=ttyMSM0,115200n8` の UART を推奨。UART が無い場合、
  adb が上がるまでは `ramoops` (DTS の `ramoops@83a00000`) 以外に手掛かりが
  ない。

## 5. USB (adb) の UDC 名

vendor の `init.target.rc` は `vendor.usb.controller a600000.dwc3` を
ハードコードし、vendor USB HAL も `a600000.dwc3` を既定値にしている。
mainline の UDC 名は gadget の parent platform device 名から作られるため、
`usb@a600000` のままだと `a600000.usb` になって一致しない。

`patches/0002-spacewar-usb-udc-name.patch` で kodiak.dtsi のノード名を
`dwc3@a600000` に変更し、UDC を `a600000.dwc3` に合わせている。これで
vendor の rc/HAL を書き換えずに configfs の `UDC` 書き込みが一致する。
ただし `/vendor/etc/init/android.hardware.usb-service.qti.rc` が参照する
`/sys/devices/platform/soc/a600000.ssusb/usb_data_enabled` は mainline では
`.../a600000.dwc3/...` になるため、その chown は失敗する（致命的ではない）。

## 6. 既知のギャップ

- **touch**: stock は focaltech `fts_ts` (DT は `focaltech,ft3680` 相当)。
  mainline 7.3 に driver は無く、DTS でもコメントアウトされている。
  `fts_tp.ko` の 7.3 向け port が必要。bring-up 直後は入力デバイス無し。
- **fingerprint**: `goodix_fp`。mainline driver 無し。今回は対象外。
- **NFC**: DTS に `nxp,pn553` / `nxp,nxp-nci-i2c` ノードはあるが未検証。
- **WiFi**: vendor は `qca_cld3_wca6750` (qcacld)。mainline は ath11k だが、
  WCN6750 firmware (`bdwlan*`, `q6*`) が `/vendor/firmware` や `modem.img`
  に見当たらない。firmware の入手性を確認するまで WiFi は保証しない。
- **BT**: `hci_qca` / `btqca` は有効。firmware (`bluetooth.img`) と
  nvm の組み合わせは未検証。
- **display/GPU**: `DRM_MSM` + `DRM_PANEL_VISIONOX_RM692E5` は built-in。
  Android 側は QTI display HAL を `drm_hwcomposer` + `minigbm` +
  freedreno/turnip に置き換える必要がある。
- **audio**: `SND_SOC_QDSP6` は有効だが、vendor の topology/ADSP 前提の
  QTI audio HAL はそのままでは動かない。topology の整備が必要。
- **camera / GNSS / Widevine / soter / CAS**: 今回の scope 外。
- **vendor modules**: `fts_tp.ko`, `goodix_fp.ko`, `qca_cld3_wlan.ko`,
  rmnet/audio dlkm などは 5.4 向けで mainline ではロードできない。

## 7. HAL 置き換えマトリクス（草案）

| 領域 | vendor (5.4 qGKI) | mainline/AOSP 側 | 状態 |
|---|---|---|---|
| kernel core | 5.4 qGKI | Linux 7.3 | ビルド可 |
| binder | vendor binder | `ANDROID_BINDERFS` + `ANDROID_BINDER_IPC` | 有効・未検証 |
| display | QTI display HAL | drm_hwcomposer + minigbm + freedreno | TODO |
| camera | camera provider 2.4 | AOSP camera2 + vendor blob | scope 外 |
| audio | QTI audio HAL + ADSP | `SND_SOC_QDSP6` + AOSP audio HAL | TODO |
| WiFi | qcacld3 | ath11k | firmware 未確認 |
| BT | QTI BT | `BT_HCIUART_QCA` | TODO |
| NFC | NXP PN553 | `NFC_NXP_NCI` (DT あり) | 未検証 |
| touch | `fts_tp.ko` | focaltech driver port | TODO |
| fingerprint | `goodix_fp.ko` | 無し | 対象外 |
| sensors | vendor multihal | AOSP sensors HAL | TODO |
| health | QTI health HAL | AOSP health HAL | TODO |
| thermal/power | libperfmgr | AOSP power HAL | TODO |
| light | Lineage light HAL | AOSP light HAL | TODO |
| vibrator | spacewar vibrator HAL | AOSP vibrator HAL | TODO |
| USB gadget | vendor `a600000.dwc3` | UDC 名を patch で一致 | 実装済み |
| CAS/Widevine | vendor CAS/widevine | software KeyMint / blob | scope 外 |

## 8. 構成ファイル

```
spacewar_mainline/
  build.sh                  config + build + artifacts + repack
  android.fragment          Android 17 kernel contract
  spacewar.fragment         SM7325 / spacewar hardware
  patches/
    0001-spacewar-abl-dtbo-ids.patch   vendor_boot base 選択用の ID
    0002-spacewar-usb-udc-name.patch   UDC を a600000.dwc3 に
  tools/pack_dtbo.py        dtbo table の作成/置換 (空 dtbo も生成可)
```

`linux-7.3/`, `linux-7.3.tar.xz`, `downloads/`, `build/`, `artifacts/`,
`tools/mkbootimg/` は `.gitignore` 済み。`lineage24_spacewar/` (4.4 GB の
ROM dump) は絶対に commit しない。
