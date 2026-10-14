#!/usr/bin/env bash
#
# build-github.sh - 100% GitHub-Hosted Runner Build Script
# Builds the Lenovo Yoga Book (YB1-X90F/X91F/X91L) Android Live ISO in GitHub Actions
#
# Steps:
#   1. Clones Yoga-Book-Linux-Kernel (submission/yogabook-x91l-v2)
#   2. Builds patched Linux 6.x kernel + modules with RT5677 & Goodix & AtomISP
#   3. Fetches SOF v2.15.1 firmware & topology for Cherry Trail RT5677
#   4. Compiles touch_keyboard_handler (Halo Keyboard daemon)
#   5. Prepares base Android x86 rootfs (Bliss OS / LineageOS x86) with portrait quirks
#   6. Packages touch-friendly rEFInd + GRUB hybrid bootable ISO
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$HOME/yb-build}"
DIST="$HERE/dist"
JOBS="$(nproc)"

KERNEL_REPO="https://github.com/Yoga-Book/Yoga-Book-Linux-Kernel.git"
KERNEL_BRANCH="submission/yogabook-x91l-v2"
SOF_TAG="v2026.09.2"
SOF_VER="2026.09.2"
REFIND_VER="0.14.2"
LINEAGE_VER="23.2"
ANDROID_VER="16"

# Verified LineageOS 23.2 (Android 16) EXT4 GSI + Android x86 live boot harness
LINEAGE_GSI_URL="${LINEAGE_GSI_URL:-https://downloads.sourceforge.net/project/misterztr-gsi/LineageOS/Android%2016/LineageOS-23.2-20260524-VANILLA-EXT4-GSI.7z}"
BOOT_HARNESS_URL="${BOOT_HARNESS_URL:-https://downloads.sourceforge.net/project/blissos-dev/Android-Generic/PC/bliss/R/15.8.6/Bliss-v15.8.6-x86_64-OFFICIAL-gapps-20231206.iso}"

say() { echo; echo "==== $* ===="; }

mkdir -p "$WORK" "$DIST"

# ---------------------------------------------------------------- 1. Compile Halo Keyboard Daemon
say "Compiling Halo Keyboard Handler"
make -C "$HERE/device/yogabook/halo-keyboard" clean || true
make -C "$HERE/device/yogabook/halo-keyboard" -j"$JOBS"
cp -v "$HERE/device/yogabook/halo-keyboard/touch_keyboard_handler" "$WORK/"

# ---------------------------------------------------------------- 2. Fetch & Build Yoga Book Kernel
say "Fetching Yoga Book Linux Kernel ($KERNEL_BRANCH)"
KSRC="$WORK/kernel-src"
if [ ! -d "$KSRC/.git" ]; then
  git clone --depth 1 --single-branch -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KSRC"
fi

say "Configuring Kernel"
cd "$KSRC"
make x86_64_defconfig

# Strip bloat and debug symbols to prevent disk exhaustion and pahole/BTF build failures
./scripts/config --disable DEBUG_INFO \
                 --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
                 --disable DEBUG_INFO_DWARF4 \
                 --disable DEBUG_INFO_DWARF5 \
                 --disable DEBUG_INFO_BTF \
                 --enable DEBUG_INFO_NONE \
                 --set-val WERROR n

# Merge our Yoga Book hardware fragment
if [ -f "$HERE/device/yogabook/YOGABOOK_x86_64/configs/kernel/yogabook.config" ]; then
  bash scripts/kconfig/merge_config.sh -m .config "$HERE/device/yogabook/YOGABOOK_x86_64/configs/kernel/yogabook.config"
  ./scripts/config --disable DEBUG_INFO \
                   --disable DEBUG_INFO_BTF \
                   --enable DEBUG_INFO_NONE \
                   --set-val WERROR n
  make olddefconfig
fi

say "Compiling Kernel (bzImage & modules)"
echo "Disk space before kernel compilation:"
df -h /
make -j"$JOBS" bzImage modules
echo "Disk space after kernel compilation:"
df -h /

MOD_STAGE="$WORK/modules-stage"
rm -rf "$MOD_STAGE"
mkdir -p "$MOD_STAGE"
make INSTALL_MOD_PATH="$MOD_STAGE" INSTALL_MOD_STRIP=1 modules_install

# ---------------------------------------------------------------- 3. Fetch SOF Firmware & Topology
say "Fetching Sound Open Firmware ($SOF_TAG) & Yoga Book RT5677 Topology"
FW_STAGE="$WORK/firmware-stage/intel/sof"
mkdir -p "$FW_STAGE"

# Download SOF release binaries (contains sof-cht-rt5677.tplg)
if curl -f -sL --retry 3 --max-time 180 -o "$WORK/sof-bin.tar.gz" \
  "https://github.com/thesofproject/sof-bin/releases/download/$SOF_TAG/sof-bin-$SOF_VER.tar.gz"; then
  tar -xzf "$WORK/sof-bin.tar.gz" -C "$WORK" 2>/dev/null || true
  cp -a "$WORK/sof-bin-$SOF_VER"/sof/v*/* "$FW_STAGE/" 2>/dev/null || true
  cp -a "$WORK/sof-bin-$SOF_VER"/sof-tplg-v*/* "$FW_STAGE/" 2>/dev/null || true
fi

# Fetch Maurizio Casciano's tested Yoga Book cht-rt5677 topology
curl -f -sL --retry 3 --max-time 60 -o "$FW_STAGE/sof-cht-rt5677.tplg" \
  "https://raw.githubusercontent.com/Yoga-Book/Yoga-Book-Sound-Open-Firmware/submission/cht-rt5677-topology2-ipc3-v1/tools/topology/topology2/production/sof-cht-rt5677.tplg" 2>/dev/null || true

# ---------------------------------------------------------------- 4. Prepare Base Android x86 System
say "Preparing LineageOS $LINEAGE_VER (Android $ANDROID_VER) System & Boot Harness"
BASE_STAGE="$WORK/android-base"
mkdir -p "$BASE_STAGE"

# Fetch boot harness for initrd.img and live boot scripts
if [ ! -f "$WORK/boot_harness.iso" ]; then
  say "Fetching Android x86 live boot harness (initrd.img)"
  curl -f -L --retry 3 --max-time 600 -o "$WORK/boot_harness.iso" "$BOOT_HARNESS_URL"
  7z x "$WORK/boot_harness.iso" -o"$BASE_STAGE" initrd.img install.img gearlock -r -y 2>/dev/null || true
fi

# Fetch LineageOS 23.2 system image
if [ ! -f "$BASE_STAGE/system.img" ]; then
  say "Fetching LineageOS 23.2 GSI ($LINEAGE_GSI_URL)"
  curl -f -L --retry 3 --max-time 600 -o "$WORK/lineage23.2.7z" "$LINEAGE_GSI_URL"
  7z x "$WORK/lineage23.2.7z" -o"$BASE_STAGE" -y 2>/dev/null || true
  SYS_RAW=$(find "$BASE_STAGE" -maxdepth 2 -name "*.img" ! -name "initrd.img" ! -name "install.img" | head -1)
  if [ -n "$SYS_RAW" ] && [ "$SYS_RAW" != "$BASE_STAGE/system.img" ]; then
    mv -v "$SYS_RAW" "$BASE_STAGE/system.img"
  fi
fi

# ---------------------------------------------------------------- 5. Stage Final Boot Files
say "Staging Bootable Media"
STAGE="$WORK/staging"
rm -rf "$STAGE"
mkdir -p "$STAGE/ANDRID" "$STAGE/bootlogs" "$STAGE/boot/grub" "$STAGE/EFI/BOOT/icons"

# Copy custom Yoga Book kernel
cp -v "$KSRC/arch/x86/boot/bzImage" "$STAGE/ANDRID/kernel"

# Copy base system image(s)
for f in system.sfs system.img gearlock install.img; do
  if [ -f "$BASE_STAGE/$f" ]; then
    cp -v "$BASE_STAGE/$f" "$STAGE/ANDRID/"
  fi
done

# Integrate custom modules into initrd
say "Repacking initrd with Yoga Book modules and Halo Keyboard files"
RDK_WORK="$WORK/rdk_work"
rm -rf "$RDK_WORK"
mkdir -p "$RDK_WORK"

if [ -f "$BASE_STAGE/initrd.img" ]; then
  (cd "$RDK_WORK" && zcat "$BASE_STAGE/initrd.img" | cpio -idmv 2>/dev/null || cpio -idmv < "$BASE_STAGE/initrd.img" 2>/dev/null || true)
fi

# Overlay our modules and firmware
mkdir -p "$RDK_WORK/lib/modules" "$RDK_WORK/lib/firmware"
cp -a "$MOD_STAGE/lib/modules/." "$RDK_WORK/lib/modules/" 2>/dev/null || true
cp -a "$FW_STAGE/." "$RDK_WORK/lib/firmware/intel/sof/" 2>/dev/null || true

# Overlay Halo keyboard binary and config
mkdir -p "$RDK_WORK/system/bin" "$RDK_WORK/system/etc/touch_keyboard"
cp -v "$WORK/touch_keyboard_handler" "$RDK_WORK/system/bin/" 2>/dev/null || true
cp -a "$HERE/device/yogabook/halo-keyboard/config/." "$RDK_WORK/system/etc/touch_keyboard/" 2>/dev/null || true

# Repack initrd.img
(cd "$RDK_WORK" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$STAGE/ANDRID/initrd.img")

# ---------------------------------------------------------------- 6. Setup rEFInd & GRUB Bootloader
say "Fetching rEFInd ($REFIND_VER)"
if [ ! -d "$WORK/refind-bin-$REFIND_VER" ]; then
  curl -sL --max-time 120 -o "$WORK/refind.zip" \
    "https://sourceforge.net/projects/refind/files/$REFIND_VER/refind-bin-$REFIND_VER.zip/download"
  unzip -q -o "$WORK/refind.zip" -d "$WORK"
fi

REF="$WORK/refind-bin-$REFIND_VER/refind"
cp -v "$REF/refind_x64.efi" "$STAGE/EFI/BOOT/BOOTX64.EFI"
cp -a "$REF/icons/." "$STAGE/EFI/BOOT/icons/"
cp -a "$WORK/refind-bin-$REFIND_VER/fonts" "$STAGE/EFI/BOOT/" 2>/dev/null || true

CMDLINE="androidboot.hardware=android_x86 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID"

cat > "$STAGE/EFI/BOOT/refind.conf" <<EOF
timeout 5
screensaver 300
resolution 1920 1200
showtools shutdown,reboot

menuentry "Yoga Book LineageOS $LINEAGE_VER (Android $ANDROID_VER)" {
    icon /EFI/BOOT/icons/os_linux.png
    loader /ANDRID/kernel
    initrd /ANDRID/initrd.img
    options "$CMDLINE quiet"
}

menuentry "Yoga Book LineageOS $LINEAGE_VER (Debug Console)" {
    icon /EFI/BOOT/icons/tool_shell.png
    loader /ANDRID/kernel
    initrd /ANDRID/initrd.img
    options "$CMDLINE DEBUG=2"
}

menuentry "Reboot" { reboot }
menuentry "Shutdown" { shutdown }
EOF

cat > "$STAGE/boot/grub/grub.cfg" <<EOF
set timeout=5
menuentry "Yoga Book LineageOS $LINEAGE_VER (Android $ANDROID_VER)" {
    linux /ANDRID/kernel $CMDLINE quiet
    initrd /ANDRID/initrd.img
}
menuentry "Yoga Book LineageOS $LINEAGE_VER (Debug Mode)" {
    linux /ANDRID/kernel $CMDLINE DEBUG=2
    initrd /ANDRID/initrd.img
}
EOF

# ---------------------------------------------------------------- 7. Create Hybrid ISO
say "Generating Hybrid ISO with make-refind-iso.sh"
ISO_NAME="YOGABOOK-LineageOS-$LINEAGE_VER-x86_64-$(date +%Y%m%d)-live.iso"
OUT_ISO="$DIST/$ISO_NAME"

FILE_ARGS=()
for f in "$STAGE/ANDRID"/*; do
  [ -f "$f" ] && FILE_ARGS+=( -f "$f" )
done

bash "$HERE/scripts/make-refind-iso.sh" \
  -o "$OUT_ISO" \
  -a "ANDRID" \
  "${FILE_ARGS[@]}" \
  -e "$STAGE"

cd "$DIST"
sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"

say "Build Complete!"
ls -lh "$DIST"
cat "$DIST/$ISO_NAME.sha256"
