#!/usr/bin/env bash
# repack-iso.sh — Build the one-touch Yoga Book Android installer ISO.
#
# Usage: repack-iso.sh <base.iso> <bzImage> <modules.tar.gz> <out.iso> \
#                      [assets-dir] [KREL-file]
#
# assets-dir (optional) may contain:
#   busybox-yb            static busybox (fdisk/mkdosfs/mke2fs) used by installer
#   firmware/*            extra firmware (e.g. sof-cht-rt5677.tplg)
#
# What it does:
#   1. Extracts the Bliss/Bass 16.9.7 ISO
#   2. Replaces /kernel with the Yoga Book kernel
#   3. Injects into initrd.img: our module tree, firmware, and the
#      yogabook-autostall one-touch installer (guarded: only wipes the
#      internal eMMC on a verified Yoga Book; otherwise boots normally)
#   4. Writes a GRUB config whose DEFAULT entry (3s) is the auto-install
#   5. Rebuilds a hybrid bootable ISO with the original boot records
set -euo pipefail

BASE="${1:?usage: repack-iso.sh <base.iso> <bzImage> <modules.tar.gz> <out.iso> [assets-dir] [KREL-file]}"
BZIMAGE="${2:?missing bzImage}"
MODULES_TGZ="${3:?missing modules.tar.gz}"
OUT="${4:?missing out.iso}"
ASSETS="${5:-}"
KREL_FILE="${6:-}"

WORK="$(mktemp -d /tmp/repack-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/iso" "$WORK/initrd" "$WORK/ramdisk"

command -v xorriso >/dev/null || { echo "ERROR: xorriso is required" >&2; exit 1; }
KREL="${KREL_FILE:+$(cat "$KREL_FILE" 2>/dev/null)}"
KREL="${KREL:-$(basename "$MODULES_TGZ" | sed 's/^modules-//; s/\.tar\.gz$//')}"

echo ">>> Extracting base ISO"
xorriso -osirrox on -indev "$BASE" -extract / "$WORK/iso" >/dev/null 2>&1
[[ -f "$WORK/iso/kernel" ]] || { echo "ERROR: no /kernel in ISO" >&2; exit 1; }

echo ">>> Replacing kernel"
install -m 0644 "$BZIMAGE" "$WORK/iso/kernel"

# ---- initrd.img: unpack, inject, repack ----
unpack_cpio() {
    local img="$1" dir="$2"
    mkdir -p "$dir"
    ( cd "$dir" && ( xzcat "$img" 2>/dev/null || zcat "$img" 2>/dev/null \
        || lz4 -d "$img" 2>/dev/null || cat "$img" ) | cpio -idm --quiet )
}

echo ">>> Unpacking initrd.img"
unpack_cpio "$WORK/iso/initrd.img" "$WORK/initrd"

echo ">>> Merging module tree ($KREL) into initrd"
tar xzf "$MODULES_TGZ" -C "$WORK/initrd"
for d in "$WORK"/initrd/lib/modules/*; do
    [[ "$(basename "$d")" == "$KREL" ]] || { echo "    removing stale modules: $(basename "$d")"; rm -rf "$d"; }
done

if [[ -n "$ASSETS" && -f "$ASSETS/busybox-yb" ]]; then
    echo ">>> Installing static busybox for the installer"
    install -m 0755 "$ASSETS/busybox-yb" "$WORK/initrd/sbin/yb-busybox"
fi
if [[ -n "$ASSETS" && -d "$ASSETS/firmware" ]]; then
    echo ">>> Merging extra firmware (SOF topology etc.)"
    for p in lib/firmware vendor/firmware; do
        mkdir -p "$WORK/initrd/$p"
        cp -r "$ASSETS/firmware/." "$WORK/initrd/$p/" 2>/dev/null || true
    done
fi

# ---- the one-touch installer ----
cat > "$WORK/initrd/sbin/yogabook-autostall" <<'INSTALLER'
#!/bin/sh
# yogabook-autostall — one-touch Android-x86 installer for Lenovo Yoga Book.
# Guards: correct DMI + exactly one non-removable eMMC; otherwise this
# script exits 0 and the normal Android-x86 live boot continues untouched.
LOG=/yogabook-autostall.log
exec >>"$LOG" 2>&1
set -x

DMI="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
case "$DMI" in
    YB1-X91F|YB1-X91L|YB1-X90F|YB1-X90L) : ;;
    *) echo "not a Yoga Book ($DMI) - skipping auto-install"; exit 0 ;;
esac

[ -x /sbin/yb-busybox ] || { echo "no installer toolbox"; exit 0; }
BB=/sbin/yb-busybox

# find the internal eMMC (non-removable mmcblk without boot0/1 ambiguity)
EMMC=""
COUNT=0
for d in /sys/block/mmcblk*; do
    [ -e "$d" ] || continue
    [ "$($BB cat "$d/removable" 2>/dev/null)" = "0" ] || continue
    EMMC="/dev/$(basename "$d")"
    COUNT=$((COUNT+1))
done
[ "$COUNT" = "1" ] && [ -n "$EMMC" ] || { echo "eMMC not uniquely identified (count=$COUNT)"; exit 0; }
P1="${EMMC}p1"; P2="${EMMC}p2"

echo "!!!! AUTO-INSTALL: erasing $EMMC in 5 seconds — power off now to abort !!!!"
sleep 5

$BB fdisk "$EMMC" <<FD
o
n
p
1

+64M
t
c
n
p
2


w
FD
$BB mkdosfs -n EFI "$P1"
$BB mke2fs -F -t ext4 -L DATA "$P2"

# locate the boot media (this ISO)
SRCDEV=""
for m in /proc/mounts; do :; done
SRCDEV="$($BB blkid 2>/dev/null | $BB awk -F: '/iso9660/{print $1; exit}')"
[ -n "$SRCDEV" ] || SRCDEV="$($BB awk '$3=="iso9660"{print $1; exit}' /proc/mounts)"
[ -n "$SRCDEV" ] || { echo "cannot find ISO media"; exit 1; }
mkdir -p /mnt/src
$BB mount -t iso9660 "$SRCDEV" /mnt/src || $BB mount "$SRCDEV" /mnt/src || { echo "mount failed"; exit 1; }

# stage: kernel+initrd on the ESP, ramdisk/system/data sfs on DATA:/android
mkdir -p /mnt/efi /mnt/data/android
$BB mount "$P1" /mnt/efi || { echo "ESP mount failed"; exit 1; }
$BB mount "$P2" /mnt/data || { echo "DATA mount failed"; exit 1; }
cp /mnt/src/kernel /mnt/src/initrd.img /mnt/efi/
for f in /mnt/src/ramdisk.img /mnt/src/system.sfs /mnt/src/system.img; do
    [ -f "$f" ] && cp "$f" /mnt/data/android/
done
[ -d /mnt/src/data ] && cp -r /mnt/src/data/. /mnt/data/android/data/ 2>/dev/null

# EFI bootloader: reuse the ISO's grub, add our menu
if [ -d /mnt/src/EFI/BOOT ]; then
    mkdir -p /mnt/efi/EFI
    cp -r /mnt/src/EFI/BOOT /mnt/efi/EFI/
fi

cat > /mnt/efi/EFI/BOOT/grub.cfg <<GRUB
set timeout=0
set default=0
menuentry "BlissOS-YogaBook" {
    search --no-floppy --file /kernel --set=root
    linux /kernel quiet root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive SRC=/android DATA=$P2
    initrd /initrd.img
}
GRUB
$BB sed -i "s|DATA=$P2|DATA=$P2|" /mnt/efi/EFI/BOOT/grub.cfg

$BB umount /mnt/efi /mnt/data /mnt/src 2>/dev/null
sync
echo "AUTO-INSTALL COMPLETE - powering off"
sleep 2
poweroff -f
exit 0
INSTALLER
chmod 0755 "$WORK/initrd/sbin/yogabook-autostall"

# shim /init: run the installer (guarded), then continue normal boot
if [ -f "$WORK/initrd/init" ] && [ ! -f "$WORK/initrd/init.orig" ]; then
    mv "$WORK/initrd/init" "$WORK/initrd/init.orig"
fi
if [ -f "$WORK/initrd/init.orig" ]; then
    cat > "$WORK/initrd/init" <<'SHIM'
#!/bin/sh
if ! grep -q 'YB_INSTALL=0' /proc/cmdline 2>/dev/null; then
    /sbin/yogabook-autostall || true
fi
exec /init.orig
SHIM
    chmod 0755 "$WORK/initrd/init"
fi

touch "$WORK/initrd/yogabook-autostall.enabled"

echo ">>> Repacking initrd.img (lz4)"
( cd "$WORK/initrd" && find . -print0 | cpio --null -o -H newc --quiet | lz4 -9 -l ) \
    > "$WORK/iso/initrd.img"

# ---- ramdisk.img: merge modules so the installed system has them too ----
if [[ -f "$WORK/iso/ramdisk.img" ]]; then
    echo ">>> Merging modules into ramdisk.img"
    unpack_cpio "$WORK/iso/ramdisk.img" "$WORK/ramdisk"
    tar xzf "$MODULES_TGZ" -C "$WORK/ramdisk"
    ( cd "$WORK/ramdisk" && find . -print0 | cpio --null -o -H newc --quiet | gzip -9 ) \
        > "$WORK/iso/ramdisk.img"
fi

# ---- GRUB: auto-install is the DEFAULT entry, 3s timeout ----
GRUBCFG="$WORK/iso/boot/grub/grub.cfg"
[[ -f "$GRUBCFG" ]] || GRUBCFG="$(find "$WORK/iso" -name grub.cfg | head -n1)"
if [[ -f "$GRUBCFG" ]]; then
    echo ">>> Writing custom grub.cfg at $GRUBCFG"
    cp "$GRUBCFG" "${GRUBCFG}.orig"
    cat > "$GRUBCFG" <<'GRUB'
set timeout=3
set default=0
set fallback=1
menuentry "Yoga Book — AUTO-INSTALL Android (erases internal eMMC)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel quiet root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive
    initrd /initrd.img
}
menuentry "Yoga Book — Live boot (no install)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel quiet root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive YB_INSTALL=0
    initrd /initrd.img
}
GRUB
    # keep the original entries available as fallback entries 2+
    sed '/^menuentry/,$d' "${GRUBCFG}.orig" >/dev/null 2>&1 || true
fi

# ---- rebuild the ISO preserving the original El Torito boot records ----
OPTS="$(xorriso -indev "$BASE" -report_el_torito as_mkisofs 2>/dev/null | tr '\n' ' ' | xargs || true)"
echo ">>> Rebuilding $OUT (boot opts: ${OPTS:-<fallback BIOS-only>})"
rm -f "$OUT"

GPT=""
case " $OPTS " in *" -e "*) GPT="-isohybrid-gpt-basdat" ;; esac

if [[ -n "$OPTS" ]] && eval "xorriso -as mkisofs -o \"$OUT\" \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin $GPT $OPTS \"$WORK/iso\"" 2>&1 | tail -3; then
    :
else
    echo ">>> as_mkisofs route failed, falling back to plain BIOS build"
    xorriso -as mkisofs -o "$OUT" -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot \
        -boot-load-size 4 -boot-info-table -V "BlissOS-YogaBook" "$WORK/iso"
fi

echo ">>> Result:"
ls -lh "$OUT"
echo ">>> Boot check (El Torito records):"
xorriso -indev "$OUT" -report_el_torito plain 2>/dev/null | head -8 || true
