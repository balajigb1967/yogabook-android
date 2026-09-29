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
# Install design (default):
#   * Android is installed onto a REMOVABLE SD CARD (mmcblk, removable=1)
#   * the internal eMMC (and any Windows install on it) is NEVER touched
#   * SD layout: p1 FAT32 ESP (grub + kernel + initrd + system.sfs),
#                p2 ext4 DATA (persistent user data)
#   * multi-boot: Volume-Up firmware menu picks SD (Android) / eMMC (Windows)
#   * an explicit GRUB entry opts into wiping the eMMC instead (YB_TARGET=emmc)
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

# ---- the guarded installer (SD default, eMMC only on explicit opt-in) ----
cat > "$WORK/initrd/sbin/yogabook-autostall" <<'INSTALLER'
#!/bin/sh
# yogabook-autostall — one-touch Android-x86 installer for Lenovo Yoga Book.
#
# Default: install to a REMOVABLE SD CARD (Windows on eMMC untouched).
# cmdline YB_TARGET=emmc switches to the destructive eMMC wipe install.
# All output goes to console so the user sees every step.
exec >/dev/console 2>&1
BB=/sbin/yb-busybox
[ -x "$BB" ] || { echo "[YB] no installer toolbox"; exit 0; }

mount -t proc proc /proc 2>/dev/null
CMD="$(cat /proc/cmdline 2>/dev/null)"
umount /proc 2>/dev/null

DMI="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
case "$DMI" in
    YB1-X91F|YB1-X91L|YB1-X90F|YB1-X90L) : ;;
    *) echo "[YB] not a Yoga Book ($DMI) - skipping auto-install"; exit 0 ;;
esac

case "$CMD" in
    *YB_TARGET=emmc*) TARGET=emmc ;;
    *)                TARGET=sd ;;
esac

# ---- pick the target device ----
if [ "$TARGET" = "emmc" ]; then
    WANT_REMOVABLE=0
    echo "[YB] MODE: wipe eMMC and install Android (WINDOWS WILL BE ERASED)"
else
    WANT_REMOVABLE=1
    echo "[YB] MODE: install to SD card (Windows on eMMC stays untouched)"
fi

TGT=""
COUNT=0
for d in /sys/block/mmcblk*; do
    [ -e "$d" ] || continue
    [ "$($BB cat "$d/removable" 2>/dev/null)" = "$WANT_REMOVABLE" ] || continue
    TGT="/dev/$(basename "$d")"
    COUNT=$((COUNT+1))
done
if [ "$TARGET" = "emmc" ]; then
    [ "$COUNT" = "1" ] && [ -n "$TGT" ] || { echo "[YB] eMMC not uniquely identified (count=$COUNT)"; exit 0; }
else
    [ "$COUNT" = "1" ] && [ -n "$TGT" ] || {
        echo "[YB] no removable SD card found (count=$COUNT) - insert one and reboot, or use the eMMC menu entry"
        exit 0
    }
fi
P1="${TGT}p1"; P2="${TGT}p2"
echo "[YB] target device: $TGT"

# ---- locate the boot media by CONTENT (skips the target) ----
mkdir -p /mnt/src
SRCDEV=""
for dev in /dev/sr0 /dev/sd[a-z] /dev/sd[a-z][0-9] /dev/mmcblk[0-9] /dev/mmcblk[0-9]p[0-9]; do
    [ -b "$dev" ] || continue
    case "$dev" in
        "$TGT"|"$P1"|"$P2") continue ;;
    esac
    if $BB mount -o ro "$dev" /mnt/src 2>/dev/null; then
        if [ -f /mnt/src/kernel ] && { [ -f /mnt/src/system.sfs ] || [ -f /mnt/src/system.img ]; }; then
            SRCDEV="$dev"
            break
        fi
        $BB umount /mnt/src 2>/dev/null
    fi
done
[ -n "$SRCDEV" ] || { echo "[YB] cannot find boot media"; exit 1; }
echo "[YB] boot media: $SRCDEV"

# refuse to install onto the medium we are booting from
case "$SRCDEV" in
    "$TGT"|"$P1"|"$P2") echo "[YB] target == boot media - refusing"; exit 1 ;;
esac

if [ "$TARGET" != "emmc" ]; then
    SIZE="$($BB blockdev --getsize64 "$TGT" 2>/dev/null || echo 0)"
    if [ "$SIZE" -lt 4000000000 ] 2>/dev/null; then
        echo "[YB] SD card too small (<4GB) - aborting"; exit 1
    fi
fi

echo "!!!! AUTO-INSTALL: erasing $TGT in 10 seconds — POWER OFF NOW TO ABORT !!!!"
sleep 10

# obliterate ALL previous installation signatures (old GRUB, Windows Boot
# Manager, stale GPT) so nothing old can be picked up by the firmware
$BB dd if=/dev/zero of="$TGT" bs=1M count=2 2>/dev/null || true

$BB fdisk "$TGT" <<FD
o
n
p
1

+256M
t
c
n
p
2


w
FD
$BB mkdosfs -n ANDROID "$P1"
$BB mke2fs -F -t ext4 -L DATA "$P2"

# ---- stage files ----
mkdir -p /mnt/efi
$BB mount "$P1" /mnt/efi || { echo "[YB] ESP mount failed"; exit 1; }
cp /mnt/src/kernel /mnt/src/initrd.img /mnt/efi/
for f in /mnt/src/ramdisk.img /mnt/src/system.sfs /mnt/src/system.img; do
    [ -f "$f" ] && cp "$f" /mnt/efi/
done

if [ -d /mnt/src/EFI/BOOT ]; then
    mkdir -p /mnt/efi/EFI
    cp -r /mnt/src/EFI/BOOT /mnt/efi/EFI/
fi

cat > /mnt/efi/EFI/BOOT/grub.cfg <<GRUB
set timeout=1
set default=0
menuentry "Android (Bass OS 16.9.7) — installed on SD" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive DATA=$P2
    initrd /initrd.img
}
menuentry "Install Android to eMMC (WIPES WINDOWS)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive YB_TARGET=emmc
    initrd /initrd.img
}
GRUB
# some firmwares read /EFI/BOOT/grub/grub.cfg instead
mkdir -p /mnt/efi/EFI/BOOT/grub 2>/dev/null || true
cp /mnt/efi/EFI/BOOT/grub.cfg /mnt/efi/EFI/BOOT/grub/grub.cfg 2>/dev/null || true
$BB umount /mnt/efi

sync
if [ "$TARGET" = "emmc" ]; then
    echo "[YB] AUTO-INSTALL COMPLETE (eMMC wiped, Android installed) - powering off"
else
    echo "[YB] AUTO-INSTALL COMPLETE (SD card ready) - remove USB stick; keep SD in"
    echo "[YB] Power on and pick the SD entry in the Volume-Up boot menu."
fi
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
mount -t proc proc /proc 2>/dev/null
if ! grep -q 'YB_INSTALL=0' /proc/cmdline 2>/dev/null; then
    echo "[YB] auto-installer starting (pass YB_INSTALL=0 to skip)..."
    /sbin/yogabook-autostall || { echo "[YB] installer did not run - continuing to live boot"; }
fi
umount /proc 2>/dev/null
if [ -x /init.orig ]; then
    exec /init.orig
elif [ -x /sbin/init ]; then
    exec /sbin/init
fi
exec sh
SHIM
    chmod 0755 "$WORK/initrd/init"
fi

touch "$WORK/initrd/yogabook-autostall.enabled"

echo ">>> Repacking initrd.img (gzip - universally supported by all kernels)"
( cd "$WORK/initrd" && find . -print0 | cpio --null -o -H newc --quiet | gzip -9 ) \
    > "$WORK/iso/initrd.img"

# ---- ramdisk.img: merge modules so the installed system has them too ----
if [[ -f "$WORK/iso/ramdisk.img" ]]; then
    echo ">>> Merging modules into ramdisk.img"
    unpack_cpio "$WORK/iso/ramdisk.img" "$WORK/ramdisk"
    tar xzf "$MODULES_TGZ" -C "$WORK/ramdisk"
    ( cd "$WORK/ramdisk" && find . -print0 | cpio --null -o -H newc --quiet | gzip -9 ) \
        > "$WORK/iso/ramdisk.img"
fi

# ---- ISO GRUB: SD install is the DEFAULT entry, 3s timeout ----
GRUBCFG="$WORK/iso/boot/grub/grub.cfg"
[[ -f "$GRUBCFG" ]] || GRUBCFG="$(find "$WORK/iso" -name grub.cfg | head -n1)"
if [[ -f "$GRUBCFG" ]]; then
    echo ">>> Writing custom grub.cfg at $GRUBCFG"
    cp "$GRUBCFG" "${GRUBCFG}.orig"
    cat > "$GRUBCFG" <<'GRUB'
set timeout=3
set default=0
set fallback=1
menuentry "Yoga Book — AUTO-INSTALL to SD card (Windows untouched)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive
    initrd /initrd.img
}
menuentry "Yoga Book — Live boot (no install)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive YB_INSTALL=0
    initrd /initrd.img
}
menuentry "Yoga Book — WIPE eMMC & install Android (erases Windows)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive YB_TARGET=emmc
    initrd /initrd.img
}
GRUB
    # UEFI firmware boots \EFI\BOOT\grub.cfg — our custom menu must be there too
    if [ -f "$WORK/iso/EFI/BOOT/grub.cfg" ]; then
        cp "$GRUBCFG" "$WORK/iso/EFI/BOOT/grub.cfg"
    fi
fi

# ---- rebuild the ISO preserving the original El Torito boot records ----
OPTS="$(xorriso -indev "$BASE" -report_el_torito as_mkisofs 2>/dev/null | tr '\n' ' ' | xargs || true)"
echo ">>> Rebuilding $OUT (boot opts: ${OPTS:-<fallback BIOS-only>})"
rm -f "$OUT"

GPT=""
case " $OPTS " in
    # -efi-boot-part --efi-boot-image: embed the El Torito UEFI image as a real
    # GPT EFI System Partition — strict firmwares (YB1 Insyde) only enumerate
    # USB sticks whose GPT has an ESP-typed partition.
    *" -e "*) GPT="-isohybrid-gpt-basdat -efi-boot-part --efi-boot-image" ;;
esac

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
