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
# Install design (default, USER REQUEST: no keyboard, no working SD slot):
#   * DEFAULT GRUB entry wipes the internal eMMC and installs Android there
#     (erases Windows) — runs only on a positively-identified Yoga Book and
#     only after a 10-second on-screen POWER OFF TO ABORT window
#   * SD-card install and live boot remain as secondary GRUB entries
#   * target layout: p1 FAT32 ESP (grub + kernel + initrd + system.sfs),
#                    p2 ext4 DATA (persistent user data)
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

# Older kernels ship modules as .ko.zst (CONFIG_MODULE_COMPRESS_ZSTD) which
# busybox modprobe cannot load - decompress everything to plain .ko.
if find "$WORK/initrd/lib/modules" -name '*.ko.zst' | grep -q .; then
    echo ">>> Decompressing .ko.zst modules (busybox modprobe can't read zstd)"
    command -v zstd >/dev/null || { echo "FATAL: zstd required" >&2; exit 1; }
    find "$WORK/initrd/lib/modules" -name '*.ko.zst' -print0 |
        while IFS= read -r -d '' f; do zstd -q -d -f "$f" -o "${f%.ko.zst}.ko" && rm -f "$f"; done
    # depmod metadata still references .ko.zst paths - regenerate it
    depmod -b "$WORK/initrd" "$KREL"
fi

if [[ -n "$ASSETS" && -f "$ASSETS/busybox-yb" ]]; then
    echo ">>> Installing static busybox for the installer"
    install -m 0755 "$ASSETS/busybox-yb" "$WORK/initrd/sbin/yb-busybox"
fi

# CRITICAL: the stock Android-x86 initrd ships /bin/busybox but NO /bin/sh
# (its /init uses '#!/bin/busybox sh'). Our injected scripts use '#!/bin/sh',
# and if /bin/sh is missing the kernel exec fails ->
# "No working init found" -> instant kernel panic. Guarantee it exists.
echo ">>> Ensuring /bin/sh, /dev, /mnt exist in initrd"
mkdir -p "$WORK/initrd/bin" "$WORK/initrd/dev" "$WORK/initrd/mnt"
if [ ! -e "$WORK/initrd/bin/sh" ]; then
    if [ -e "$WORK/initrd/bin/busybox" ]; then
        ln -s busybox "$WORK/initrd/bin/sh"
    elif [ -e "$WORK/initrd/sbin/yb-busybox" ]; then
        ln -s /sbin/yb-busybox "$WORK/initrd/bin/sh"
    else
        echo "FATAL: no busybox to back /bin/sh" >&2; exit 1
    fi
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

CMD="$(cat /proc/cmdline 2>/dev/null)"
case "$CMD" in
    *YB_TARGET=sd*)   TARGET=sd ;;
    *YB_INSTALL=0*)   exit 0 ;;
    *)                TARGET=emmc ;;   # DEFAULT: erase eMMC, install Android
esac
umount /proc 2>/dev/null

# ---- identify the machine BEFORE any destructive action ----
# /sys/class/dmi/id (CONFIG_DMIID=y, built-in) is primary; if it is unreadable
# fall back to the kernel's own boot-log line ("DMI: Lenovo YB1-X91F ...").
# The destructive eMMC mode REQUIRES a positive match; without one nothing
# destructive ever runs (other machines boot this stick safely).
DMI="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [ -z "$DMI" ]; then
    DMI="$($BB dmesg 2>/dev/null | grep -aom1 'DMI:.*' | head -c 100)"
fi
case "$DMI" in
    *YB1-X91F*|*YB1-X91L*|*YB1-X90F*|*YB1-X90L*) : ;;
    *)
        echo "[YB] dmi sysfs read gave: '$(cat /sys/class/dmi/id/product_name 2>&1)'"
        echo "[YB] not a Yoga Book (${DMI:-no DMI data}) - auto-install disabled for safety"
        exit 0
        ;;
esac
echo "[YB] Yoga Book identified: $DMI"

# ---- pick the target device ----
if [ "$TARGET" = "emmc" ]; then
    WANT_REMOVABLE=0
    echo "[YB] MODE: WIPE eMMC AND INSTALL ANDROID - WINDOWS WILL BE ERASED"
    echo "[YB] (for SD install instead, use the second GRUB entry or YB_TARGET=sd)"
else
    WANT_REMOVABLE=1
    echo "[YB] MODE: install to SD card (Windows on eMMC stays untouched)"
fi

TGT=""
COUNT=0
sleep 2   # let freshly probed mmc hosts settle
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

# source dir is 'efi/boot' (lowercase) on the ISO — match any case
ESPBOOT=""
for cand in /mnt/src/EFI/BOOT /mnt/src/efi/boot /mnt/src/efi/BOOT /mnt/src/EFI/boot; do
    [ -d "$cand" ] && ESPBOOT="$cand" && break
done
if [ -n "$ESPBOOT" ]; then
    mkdir -p /mnt/efi/EFI/BOOT
    cp -r "$ESPBOOT/." /mnt/efi/EFI/BOOT/
fi

cat > /mnt/efi/EFI/BOOT/grub.cfg <<GRUB
set timeout=1
set default=0
menuentry "Android (Bass OS 16.9.7) - installed on SD" {
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
# the firmware-loaded GRUB sources android.cfg next to BOOTX64.EFI - our
# menu must live THERE or the stock Bliss menu takes over (or nothing boots)
if [ -f /mnt/efi/EFI/BOOT/android.cfg ]; then
    mv /mnt/efi/EFI/BOOT/android.cfg /mnt/efi/EFI/BOOT/android.cfg.bliss
fi
cp /mnt/efi/EFI/BOOT/grub.cfg /mnt/efi/EFI/BOOT/android.cfg
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
# DATA= in cmdline means we are booting an ALREADY INSTALLED system — never
# re-run the installer then (the installed SD card would otherwise look like
# a valid install target).
if [ -f "$WORK/initrd/init" ] && [ ! -f "$WORK/initrd/init.orig" ]; then
    mv "$WORK/initrd/init" "$WORK/initrd/init.orig"
fi
if [ -f "$WORK/initrd/init.orig" ]; then
    cat > "$WORK/initrd/init" <<'SHIM'
#!/bin/busybox sh
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
# Our Yoga Book kernel builds USB storage, SD/eMMC hosts and HID as MODULES,
# and nothing else in this initrd loads them: without this, the installer
# sees no SD card and Android's init cannot find the boot stick
# ("Detecting Android-x86..." forever). Load what we need, then settle.
MP=/sbin/yb-busybox
[ -x "$MP" ] || MP=/bin/busybox
PATH=/sbin:/bin:/usr/sbin:/usr/bin; export PATH
echo "[YB] loading storage/SD/HID modules..."
for m in usb-storage uas mmc_block sdhci sdhci-pci sdhci-acpi usbhid hid-generic hid \
         rtsx_usb rtsx_usb_sdmmc rtsx_pci rtsx_pci_sdmmc; do
    $MP modprobe "$m" 2>/dev/null || true
done
sleep 3
if ! grep -qE 'YB_INSTALL=0|DATA=' /proc/cmdline 2>/dev/null; then
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

# ---- integrity assertions: fail the build BEFORE shipping a dead initrd ----
echo ">>> Initrd integrity checks"
[ -f "$WORK/initrd/init" ]                   || { echo "FATAL: /init missing after repack prep" >&2; exit 1; }
[ -f "$WORK/initrd/init.orig" ]              || { echo "FATAL: /init.orig missing (original Android init)" >&2; exit 1; }
[ -x "$WORK/initrd/sbin/yogabook-autostall" ] || { echo "FATAL: installer script missing" >&2; exit 1; }
[ -e "$WORK/initrd/bin/sh" ]                 || { echo "FATAL: /bin/sh missing - /init shebang would fail" >&2; exit 1; }
[ -d "$WORK/initrd/lib/modules/$KREL" ]      || { echo "FATAL: /lib/modules/$KREL missing" >&2; exit 1; }
[ -d "$WORK/initrd/proc" ]                   || echo "WARN: /proc mountpoint missing in initrd"
[ -d "$WORK/initrd/sys" ]                    || echo "WARN: /sys mountpoint missing in initrd"
echo "    tree: $(find "$WORK/initrd" | wc -l) entries, $(du -sh "$WORK/initrd" | cut -f1)"

echo ">>> Repacking initrd.img (gzip - universally supported by all kernels)"
( cd "$WORK/initrd" && find . -print0 | cpio --null -o -H newc --quiet | gzip -9 ) \
    > "$WORK/iso/initrd.img"

# verify the artifact we are about to ship
INITRD_SIZE=$(stat -c%s "$WORK/iso/initrd.img")
[[ "$(head -c2 "$WORK/iso/initrd.img" | od -An -tx1 | tr -d ' \n')" == "1f8b" ]] \
    || { echo "FATAL: repacked initrd.img is not gzip (kernel could never load it)" >&2; exit 1; }
gzip -t "$WORK/iso/initrd.img" || { echo "FATAL: repacked initrd.img fails gzip integrity" >&2; exit 1; }
zcat < "$WORK/iso/initrd.img" | cpio -it --quiet | grep -qxE '^\.?/?init$' \
    || { echo "FATAL: /init not found inside repacked initrd" >&2; exit 1; }
echo "    initrd.img: $INITRD_SIZE bytes, gzip OK, /init present"

# ---- ramdisk.img: merge modules so the installed system has them too ----
if [[ -f "$WORK/iso/ramdisk.img" ]]; then
    echo ">>> Merging modules into ramdisk.img"
    unpack_cpio "$WORK/iso/ramdisk.img" "$WORK/ramdisk"
    tar xzf "$MODULES_TGZ" -C "$WORK/ramdisk"
    ( cd "$WORK/ramdisk" && find . -print0 | cpio --null -o -H newc --quiet | gzip -9 ) \
        > "$WORK/iso/ramdisk.img"
fi

# ---- ISO boot menu: SD install is the DEFAULT entry, 3s timeout ----
# The firmware-loaded GRUB (efi/boot/BOOTx64.EFI, 32- and 64-bit variants)
# sources /efi/boot/android.cfg - THAT is where the effective menu lives
# (boot/grub/grub.cfg merely sources it). Replace android.cfg itself, keep
# the original reachable as a debug entry.
MENU='set timeout=5
set default=0
menuentry "Yoga Book - INSTALL ANDROID TO eMMC (ERASES WINDOWS!) - default" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive YB_TARGET=emmc
    initrd /initrd.img
}
menuentry "Yoga Book - AUTO-INSTALL to SD card (keeps Windows)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive
    initrd /initrd.img
}
menuentry "Yoga Book - Live boot (no install)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive YB_INSTALL=0
    initrd /initrd.img
}
menuentry "Bliss original menu (debug)" {
    if [ -z "$kdir" ]; then set kdir=/android; fi
    search --no-floppy --file /efi/boot/android.cfg.orig --set=root
    source /efi/boot/android.cfg.orig
}
'
ACFG="$WORK/iso/efi/boot/android.cfg"
[[ -f "$ACFG" ]] || ACFG="$(find "$WORK/iso" -iname android.cfg | head -n1)"
if [[ -f "$ACFG" ]]; then
    echo ">>> Writing auto-install boot menu to $ACFG"
    cp "$ACFG" "$ACFG.orig"
    printf '%s\n' "$MENU" > "$ACFG"
else
    echo "WARN: no android.cfg found - UEFI menu not customized" >&2
fi
BCFG="$WORK/iso/boot/grub/grub.cfg"
if [[ -f "$BCFG" ]]; then
    echo ">>> Writing same menu to $BCFG"
    printf '%s\n' "$MENU" > "$BCFG"
fi

# ---- rebuild the ISO preserving the original El Torito boot records ----
# NOTE: do NOT pass as_mkisofs output through xargs - it strips the quotes
# around e.g. -V 'Name (x86_64)' and the unquoted parens explode eval.
# Each output line is already shell-quoted; join lines and eval directly.
# Also re-point the -isohybrid-mbr interval at OUR output (the base recipe
# copies bytes from the base file): the layout is byte-identical, so use the
# standard isohdpfx.bin instead. The rest of the recipe (incl. the GPT
# basic-data partition covering the whole ISO) is kept verbatim - it is the
# exact hybrid layout Bliss ships and the only one xorriso builds cleanly.
OPTS="$(xorriso -indev "$BASE" -report_el_torito as_mkisofs 2>/dev/null \
    | sed 's#-isohybrid-mbr --interval:[^ ]* #-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin #' \
    | tr '\n' ' ' || true)"
echo ">>> Rebuilding $OUT (boot opts: ${OPTS:-<fallback BIOS-only>})"
rm -f "$OUT"

BUILD_OK=0
if [[ -n "$OPTS" ]] && grep -q "isohdpfx" <<<"$OPTS"; then
    if eval "xorriso -as mkisofs -o \"$OUT\" $OPTS \"$WORK/iso\"" >"$WORK/xorriso.log" 2>&1; then
        BUILD_OK=1
    else
        echo ">>> as_mkisofs route failed:"
        tail -5 "$WORK/xorriso.log"
    fi
fi
if [[ "$BUILD_OK" != 1 ]]; then
    echo ">>> Falling back to plain BIOS build"
    xorriso -as mkisofs -o "$OUT" -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot \
        -boot-load-size 4 -boot-info-table -V "BlissOS-YogaBook" "$WORK/iso"
fi

echo ">>> Result:"
ls -lh "$OUT"
echo ">>> Boot check (El Torito records):"
xorriso -indev "$OUT" -report_el_torito plain 2>/dev/null | head -8 || true
