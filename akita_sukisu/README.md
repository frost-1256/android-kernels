# Pixel 8a (akita) SukiSU Ultra + SUSFS kernel

Google Pixel 8a (akita / Tensor G3) 向けの **GKI 6.1** カーネルに
**SukiSU Ultra** と **SUSFS** を組み込んで GitHub Actions でビルドする構成。

ローカルでのカーネルソース・ツールチェーン・ファームウェアのダウンロードは不要。
ビルドはすべて Actions 上で完結する。

動作確認済みビルド: [`akita-sukisu-3`](https://github.com/frost-1256/android-kernels/releases/tag/akita-sukisu-3)
(kernel `6.1.176-android14-11-g7d827700fd2d`, SukiSU builtin, SUSFS v2.3.0, KPM off)。
実機での起動確認はまだ。

## 対象

| 項目 | 値 |
|---|---|
| 端末 | Pixel 8a (`akita`) |
| ROM | Android 16 系 (stock / GKI 2.0) |
| カーネル | ACK `android14-6.1` 系 (GKI 6.1) |
| root | SukiSU Ultra `builtin` ブランチ |
| hiding | susfs4ksu `gki-android14-6.1` (v2.3.x) |
| 出力 | `boot.img` / `boot-avb.img` / AnyKernel3 zip / `Image` / `.config` |

> **注意:** これは GKI (共通カーネル) のみを差し替える構成。
> Pixel 8a の `vendor_dlkm` / `system_dlkm` / `vendor_kernel_boot` / `dtbo` は
> ストックのまま使う。GKI の KMI は固定なので、同じ `android14-6.1` 系なら
> `CONFIG_MODVERSIONS` により vendor モジュールはロードできる。
> ただしビルド元ブランチが端末のカーネルと大きく離れていると起動しない可能性がある。

## ビルド

GitHub の **Actions → Build Pixel 8a (akita) SukiSU Ultra + SUSFS → Run workflow**。

主な入力:

- `kernel_ref`: ACK のブランチ。既定は `android14-6.1-2026-09` (6.1.176)。
  端末の `uname -r` が `6.1.17x-android14-...` ならこのままでよい。
  最新 LTS にしたい場合は `android14-6.1` を指定する。
- `sukisu_ref`: **`builtin` のまま**にする。SUSFS は `builtin` (manual hook) 前提。
  `main` (kprobe) では SUSFS のカーネルパッチと噛み合わない。
- `sukisu_commit` / `susfs_commit`: 既定で動作確認済みの commit に pin してある
  (`ce75122...` / `b57ed19...`)。空欄にするとブランチ先頭を使う。
- `susfs_ref`: `gki-android14-6.1`。
- `kpm`: 通常は off。on にするとビルド後に `Image` へ KPM パッチを当てる。
- `make_release`: on なら `akita-sukisu-<run_number>` タグで Release に添付する。

成果物 (Actions の artifact / Release):

- `*-boot.img` … `fastboot flash boot` 用 (header v4、ramdisk なし)
- `*-boot-avb.img` … AVB hash footer 付き・64MiB にパディング済み
  (unlocked bootloader 用。署名は test key なので AVB 検証は通らない)
- `*-AnyKernel3.zip` … Kernel Flasher 等で現在の boot を書き換える用
- `*-Image` … 生カーネル
- `*-kernel.config`, `build-info.txt`, `SHA256SUMS.txt`

## 書き込み

前提: bootloader unlock 済み。**必ず現在の boot をバックアップ**する。

```sh
# 端末を fastboot モードにして
fastboot devices
fastboot flash boot akita-sukisu-susfs-<ver>-boot.img
fastboot reboot
```

AVB footer 付きを使う場合:

```sh
fastboot flash boot akita-sukisu-susfs-<ver>-boot-avb.img
```

AnyKernel3 zip は Kernel Flasher などの AK3 対応フラッシャーから。

起動確認:

```sh
adb shell uname -a
adb shell su -c id
```

SukiSU Ultra の Manager APK (v4.2.1 系) をインストールし、
SUSFS の設定は Manager の SuSFS 画面から行う。

## 復旧

ストックの `boot.img` を同じスロットに焼き戻す。

```sh
fastboot flash boot stock-boot.img
fastboot reboot
```

起動しない場合は A/B のもう一方のスロットに切り替えるか、
Pixel の factory image を `flash-all` で戻す。

## 仕組み / 注意点

- SukiSU は `kernel/setup.sh` で `common/drivers/kernelsu` にリンクされる。
- SUSFS は `susfs4ksu` の `kernel_patches/fs/*` と `include/linux/*` をコピーし、
  `50_add_susfs_in_gki-android14-6.1.patch` を `common` に適用する。
- `android/abi_gki_protected_exports_*` を削除する (Wi-Fi などの vendor モジュール対策)。
- ビルドは `make O=out gki_defconfig && make O=out Image`。
  `CONFIG_LTO_CLANG_THIN=y` を明示している。
- AVB は AOSP test key (取得できない場合は生成鍵)。unlocked bootloader 前提で、
  ロック状態では検証を通らない。
- セキュリティパッチは `kernel_ref` のブランチ時点。最新がよい場合は
  `android14-6.1` を指定するが、SUSFS パッチの fuzz 適用に失敗する場合は
  日付ブランチへ戻す。

## ローカルで同じビルドを走らせる場合

```sh
KERNEL_REF=android14-6.1-2026-09 bash akita_sukisu/build.sh
```

`~/.work/akita` にソース、`akita_sukisu/artifacts/` に成果物ができる。
(ローカル実行は数 GB のダウンロードを伴う)
