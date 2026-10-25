# Pixel 6 Pro (raven) Evolution X — SukiSU Ultra + SUSFS kernel

Google Pixel 6 Pro (raven / Tensor GS101) の **Evolution X** 向けに、
**GKI 6.1** カーネルへ **SukiSU Ultra** と **SUSFS** を組み込んで
GitHub Actions でビルドする構成。`akita_sukisu` の姉妹構成。

ローカルでのカーネルソース・ツールチェーンのダウンロードは不要。
ビルドはすべて Actions 上で完結する。

> **状態: 未ビルド・実機未確認。** 最初の Actions 実行で要確認。

## 対象

| 項目 | 値 |
|---|---|
| 端末 | Pixel 6 Pro (`raven`) |
| ROM | Evolution X 11 (Android 16) |
| 純正カーネル | `6.1.145-android14-11-gedaaac4d5c85-ab16017558`（EvoX の boot.img より実測） |
| カーネル | ACK `android14-6.1-2025-09`（= 6.1.145、純正と同一 LTS） |
| root | SukiSU Ultra `builtin` ブランチ |
| hiding | susfs4ksu `gki-android14-6.1` (v2.3.x) |
| 出力 | `boot.img` / `boot-avb.img` / AnyKernel3 zip / `Image` / `.config` |

> **注意:** これは GKI (共通カーネル) のみを差し替える構成。
> raven の `vendor_boot` / `vendor_dlkm` / `system_dlkm` / `dtbo` は
> EvoX 純正のまま使う。GKI の KMI は固定なので、同じ `android14-6.1` 系なら
> vendor モジュールはロードできるはずだが、
> 純正カーネルが Pixel 側ビルド（`android-gs-raviole-6.1`）由来のため、
> 起動しない可能性は残る。その場合は純正 `boot.img` を焼き戻せば復旧する。

## ビルド

GitHub の **Actions → Build Pixel 6 Pro (raven) Evolution X SukiSU Ultra + SUSFS → Run workflow**。

主な入力:

- `kernel_ref`: 既定は `android14-6.1-2025-09` (6.1.145)。
  EvoX 純正カーネルと LTS を合わせるための選択。新しい LTS に上げたい場合は
  `android14-6.1` 等を指定する（vendor モジュールとの相性リスクは上がる）。
- `sukisu_ref`: **`builtin` のまま**にする。SUSFS は `builtin` (manual hook) 前提。
- `sukisu_commit` / `susfs_commit`: 既定は `akita_sukisu` で実績のある commit
  (`ce75122...` / `b57ed19...`)。空欄にするとブランチ先頭を使う。
- `susfs_ref`: `gki-android14-6.1`。
- `kpm`: 通常は off。
- `make_release`: on なら `raven-evox-<run_number>` タグで Release に添付する。

成果物 (Actions の artifact / Release):

- `*-boot.img` … `fastboot flash boot` 用 (header v4、ramdisk なし。
  EvoX 純正 boot.img と同じく os_version=0 / cmdline 空)
- `*-boot-avb.img` … AVB hash footer 付き・64MiB パディング済み
  (unlocked bootloader 用。署名は test key)
- `*-AnyKernel3.zip` … Kernel Flasher 等で現在の boot を書き換える用
  (ramdisk は vendor_boot 側なので、AK3 は split_boot + flash_boot で kernel のみ差し替え)
- `*-Image` … 生カーネル
- `*-kernel.config`, `build-info.txt`, `SHA256SUMS.txt`

## 書き込み

前提: bootloader unlock 済み。**必ず現在の boot をバックアップ**する
(EvoX の boot.img が復旧用になる)。

```sh
fastboot flash boot raven-evox-sukisu-susfs-<ver>-boot.img
fastboot reboot
```

起動確認:

```sh
adb shell uname -a
adb shell su -c id
```

## 復旧

EvoX 純正の `boot.img` を同じスロットに焼き戻す。

```sh
fastboot flash boot stock-evox-boot.img
fastboot reboot
```

## 仕組み / 注意点

- 仕組みは `akita_sukisu/build.sh` と同一 (SukiSU は `kernel/setup.sh`、
  SUSFS は `susfs4ksu` のパッチ適用、`make gki_defconfig && make Image`)。
- 違いは対象まわりだけ: 既定ブランチ (6.1.145)、boot.img の os_version を
  純正に合わせて付けないこと、AK3 の device check が `raven` で
  本リポジトリ同梱の `anykernel.sh` を使うこと。
- `android/abi_gki_protected_exports_*` を削除する (vendor モジュール対策)。

## ローカルで同じビルドを走らせる場合

```sh
KERNEL_REF=android14-6.1-2025-09 bash raven_evox/build.sh
```

`~/.work/raven` にソース、`raven_evox/artifacts/` に成果物ができる。
