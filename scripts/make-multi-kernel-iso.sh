#!/usr/bin/env bash
# Assemble the final multi-kernel Yoga Book ISO.
#
# 1. Builds 1-2 EXTRA kernel versions (kernel.org stable) using the config
#    produced by the Android build (so module sets match), with a minimal
#    boot ramdisk carrying their modules.
# 2. Stages rEFInd (from the official binary distribution) with a touch menu:
#      - Yoga Book kernel (default, full modules, from the Android build)
#      - Extra kernel(s) (rescue/diagnostics)
#      - Debug / console / copy-to-RAM variants
# 3. Calls scripts/make-refind-iso.sh to produce the hybrid USB/SD image.
#
# Env:
#   SRC             Android source root (default $HOME/lineage)
#   EXTRA_KERNELS   space separated stable versions (default "6.12.57")
#   REFIND_VER      rEFInd version (default 0.14.2)
set -euo pipefail

SRC="${SRC:-$HOME/lineage}"
OUT="$SRC/out/target/product/YOGABOOK_x86_64"
ANDROID_DIR="ANDRID"
EXTRA_KERNELS="${EXTRA_KERNELS:-6.12.57}"
REFIND_VER="${REFIND_VER:-0.14.2}"
WORK="$SRC/out/yogabook-iso"
DIST="$SRC/dist"

[ -f "$OUT/system.img" ] || { echo "ERROR: build output not found at $OUT"; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/staging/$ANDROID_DIR" "$WORK/refind" "$DIST"

say() { echo; echo "== $* =="; }

# ---------------------------------------------------------------- rEFInd
say "Fetching rEFInd $REFIND_VER"
cd "$WORK"
if [ ! -d "refind-bin-$REFIND_VER" ]; then
  curl -sL --max-time 300 -o refind.zip \
    "https://sourceforge.net/projects/refind/files/$REFIND_VER/refind-bin-$REFIND_VER.zip/download"
  unzip -q -o refind.zip
fi
REF="refind-bin-$REFIND_VER/refind"
mkdir -p "$WORK/staging/EFI/BOOT/icons"
cp "$REF/refind_x64.efi" "$WORK/staging/EFI/BOOT/BOOTX64.EFI"
cp -a "$REF/icons/." "$WORK/staging/EFI/BOOT/icons/"
cp -a "refind-bin-$REFIND_VER/fonts" "$WORK/staging/EFI/BOOT/" 2>/dev/null || true

# ---------------------------------------------------------------- primary kernel files
say "Staging primary kernel + images"
cp -L "$OUT/kernel" "$WORK/staging/$ANDROID_DIR/"
cp -L "$OUT/ramdisk-all-combined.img" "$WORK/staging/$ANDROID_DIR/" 2>/dev/null \
  || cp -L "$OUT/ramdisk.img" "$WORK/staging/$ANDROID_DIR/ramdisk-all-combined.img"
cp -L "$OUT"/system.img "$OUT"/vendor.img "$WORK/staging/$ANDROID_DIR/" 2>/dev/null || true
for f in system_dlkm.img vendor_dlkm.img; do
  [ -f "$OUT/$f" ] && cp -L "$OUT/$f" "$WORK/staging/$ANDROID_DIR/"
done
# firmware image if the build produced one
for f in "$OUT/firmware.img" "$OUT/linux-firmware.img"; do
  [ -f "$f" ] && cp -L "$f" "$WORK/staging/$ANDROID_DIR/" && break
done

# ---------------------------------------------------------------- extra kernels
KCFG="$OUT/obj/KCONFIG_OBJ/debian-filtered.config"
[ -f "$OUT/.config" ] || true
BUILD_CFG="$(find "$OUT/obj" -maxdepth 3 -name '.config' 2>/dev/null | head -1 || true)"

build_extra_kernel() {
  local ver="$1"
  local kdir="$WORK/kernels/$ver"
  local tarball="linux-$ver.tar.xz"
  say "Building extra kernel $ver"
  mkdir -p "$WORK/kernels"
  if [ ! -d "$kdir" ]; then
    curl -sL --max-time 900 -o "$WORK/kernels/$tarball" \
      "https://cdn.kernel.org/pub/linux/kernel/v6.x/$tarball" || \
    curl -sL --max-time 900 -o "$WORK/kernels/$tarball" \
      "https://cdn.kernel.org/pub/linux/kernel/v5.x/$tarball"
    tar -xf "$WORK/kernels/$tarball" -C "$WORK/kernels"
  fi
  # base config: the one the Android build used for the primary kernel
  local base_cfg="$BUILD_CFG"
  [ -n "$base_cfg" ] || base_cfg="$KCFG"
  cp "$base_cfg" "$kdir/.config"
  make -C "$kdir" olddefconfig >/dev/null
  make -C "$kdir" -j"$(nproc)" bzImage modules >/dev/null
  # minimal ramdisk with this kernel's modules (boot media + input + storage)
  local rdk="$WORK/rdk-$ver"
  rm -rf "$rdk"; mkdir -p "$rdk/lib/modules/$ver"
  make -C "$kdir" INSTALL_MOD_PATH="$rdk" modules_install >/dev/null
  mkdir -p "$WORK/staging/$ANDROID_DIR/kernels/$ver"
  cp "$kdir/arch/x86/boot/bzImage" "$WORK/staging/$ANDROID_DIR/kernels/$ver/kernel"
  ( cd "$rdk" && find . | cpio -o -H newc 2>/dev/null | gzip > \
      "$WORK/staging/$ANDROID_DIR/kernels/$ver/ramdisk.img" )
}

for ver in $EXTRA_KERNELS; do
  build_extra_kernel "$ver" || echo "WARNING: kernel $ver failed; continuing with fewer entries"
done

# ---------------------------------------------------------------- refind/grub configs
say "Generating boot menus"
CMDLINE_COMMON="androidboot.android_dir=$ANDROID_DIR"
STAGE_CMDLINE="$CMDLINE_COMMON $ANDROID_DIR_CMDLINE_EXTRA"

gen_refind_conf() {
  local conf="$1"
  cp "$HERE/device/yogabook/YOGABOOK_x86_64/configs/refind/refind.conf" "$conf"
  {
    echo
    echo "menuentry \"Yoga Book Android 16\" {"
    echo "    icon /EFI/BOOT/icons/os_linux.png"
    echo "    loader /$ANDROID_DIR/kernel"
    echo "    initrd /$ANDROID_DIR/ramdisk-all-combined.img"
    echo "    options \"$CMDLINE_COMMON androidboot.mount_system=imgs androidboot.mount_userdata=tmpfs androidboot.mount_firmware=img androidboot.save_early_logs=1\""
    echo "}"
    echo
    echo "menuentry \"Yoga Book Android 16 (debug + logs)\" {"
    echo "    icon /EFI/BOOT/icons/tool_shell.png"
    echo "    loader /$ANDROID_DIR/kernel"
    echo "    initrd /$ANDROID_DIR/ramdisk-all-combined.img"
    echo "    options \"$CMDLINE_COMMON androidboot.mount_system=imgs androidboot.mount_userdata=tmpfs androidboot.mount_firmware=img androidboot.save_early_logs=1 androidboot.insecure_adb=true androidboot.mode=console\""
    echo "}"
    echo
    echo "menuentry \"Yoga Book Android 16 (copy system to RAM)\" {"
    echo "    icon /EFI/BOOT/icons/os_linux.png"
    echo "    loader /$ANDROID_DIR/kernel"
    echo "    initrd /$ANDROID_DIR/ramdisk-all-combined.img"
    echo "    options \"$CMDLINE_COMMON androidboot.mount_system=imgs_ram androidboot.mount_userdata=tmpfs androidboot.mount_firmware=img_ram androidboot.save_early_logs=1\""
    echo "}"
    for ver in $EXTRA_KERNELS; do
      [ -f "$WORK/staging/$ANDROID_DIR/kernels/$ver/kernel" ] || continue
      echo
      echo "menuentry \"Android 16 - extra kernel $ver (rescue)\" {"
      echo "    icon /EFI/BOOT/icons/os_unknown.png"
      echo "    loader /$ANDROID_DIR/kernels/$ver/kernel"
      echo "    initrd /$ANDROID_DIR/kernels/$ver/ramdisk.img"
      echo "    options \"$CMDLINE_COMMON androidboot.mount_system=imgs androidboot.mount_userdata=tmpfs androidboot.mount_firmware=img\""
      echo "}"
    done
    echo
    echo "menuentry \"Reboot\" { reboot }"
    echo "menuentry \"Shutdown\" { shutdown }"
  } >> "$conf"
}
gen_refind_conf "$WORK/staging/EFI/BOOT/refind.conf"

# GRUB (BIOS fallback) config
mkdir -p "$WORK/staging/boot/grub"
cat > "$WORK/staging/boot/grub/grub.cfg" <<EOF
menuentry "Yoga Book Android 16" {
    linux /$ANDROID_DIR/kernel $CMDLINE_COMMON androidboot.mount_system=imgs androidboot.mount_userdata=tmpfs androidboot.mount_firmware=img
    initrd /$ANDROID_DIR/ramdisk-all-combined.img
}
menuentry "Yoga Book Android 16 (debug + logs)" {
    linux /$ANDROID_DIR/kernel $CMDLINE_COMMON androidboot.mount_system=imgs androidboot.mount_userdata=tmpfs androidboot.mount_firmware=img androidboot.save_early_logs=1 androidboot.insecure_adb=true androidboot.mode=console
    initrd /$ANDROID_DIR/ramdisk-all-combined.img
}
EOF

# ---------------------------------------------------------------- assemble
say "Assembling hybrid ISO"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# split the staging tree: extras (EFI/, boot/, bootlogs/) vs android dir files
mkdir -p "$WORK/extras"
mv "$WORK/staging/EFI" "$WORK/extras/EFI"
mv "$WORK/staging/boot" "$WORK/extras/boot"
mkdir -p "$WORK/extras/bootlogs"

FILE_ARGS=()
for f in "$WORK/staging/$ANDROID_DIR"/*; do
  [ -f "$f" ] && FILE_ARGS+=( -f "$f" )
done

ISO="$DIST/YOGABOOK-x86_64-$(date +%Y%m%d)-live.iso"
bash "$HERE/scripts/make-refind-iso.sh" -o "$ISO" -a "$ANDROID_DIR" \
  "${FILE_ARGS[@]}" -e "$WORK/extras"

sha256sum "$ISO" > "$ISO.sha256"
ls -lh "$ISO" "$ISO.sha256"
say "Done"
