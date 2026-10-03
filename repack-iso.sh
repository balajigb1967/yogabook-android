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

# ---- SLIM INITRD ----
# The initramfs must stay small: a ~176MB initrd (the full 7.2.0 module tree)
# takes ~a minute to load+unpack and is the prime suspect for the firmware's
# GRUB failing to load it on the Yoga Book (field: kernel panic right after
# GRUB). The boot path only needs storage/SD/HID/filesystem modules - exactly
# the modprobe list the shim uses - so keep only those (resolved WITH their
# dependencies from the full tree via kmod) and let the FULL tree ship in
# ramdisk.img for the installed/live Android system.
# YB_SLIM_INITRD=0 restores the fat initrd (debugging only).
if [[ "${YB_SLIM_INITRD:-1}" = "1" ]]; then
    MODDIR="$WORK/initrd/lib/modules/$KREL"
    echo ">>> Pruning initrd modules to the boot-critical set"
    mkdir -p "$WORK/mroot/lib/modules"
    mv "$MODDIR" "$WORK/mroot/lib/modules/$KREL"
    mkdir -p "$MODDIR"
    for meta in modules.builtin modules.builtin.modinfo modules.order; do
        if [ -f "$WORK/mroot/lib/modules/$KREL/$meta" ]; then
            cp "$WORK/mroot/lib/modules/$KREL/$meta" "$MODDIR/"
        fi
    done
    KEEPLIST="usb-storage uas usbhid hid-generic hid usbcore usb-common \
mmc_block mmc_core sdhci sdhci-pci sdhci-acpi sdhci-pltfm \
rtsx_usb rtsx_usb_sdmmc rtsx_pci rtsx_pci_sdmmc \
sd_mod sr_mod cdrom scsi_mod ata_piix ahci libata nvme nvme_core \
virtio_blk virtio_pci virtio virtio_ring \
xhci-pci xhci-hcd ehci-pci ehci-hcd uhci-hcd \
hid-multitouch i2c-hid intel-lpss intel-lpss-pci intel-lpss-acpi \
isofs udf nls_cp437 nls_ascii nls_base nls_iso8859-1 nls_utf8 vfat fat erofs"
    for name in $KEEPLIST; do
        modprobe -d "$WORK/mroot" -S "$KREL" --show-depends "$name" 2>/dev/null |
        while IFS= read -r line; do
            case "$line" in
                insmod\ *)
                    f="${line#insmod }"; f="${f%% *}"
                    rel="${f##*/lib/modules/$KREL/}"
                    if [ "$rel" != "$f" ]; then
                        dst="$MODDIR/$rel"
                        if [ ! -f "$dst" ]; then mkdir -p "$(dirname "$dst")"; cp "$f" "$dst"; fi
                    fi
                    ;;
            esac
        done || true
    done
    rm -rf "$WORK/mroot"
    [ -d "$MODDIR" ] || mkdir -p "$MODDIR"
    find "$MODDIR" -type d -empty -delete 2>/dev/null || true
    depmod -b "$WORK/initrd" "$KREL"
    echo "    slim initrd modules: $(find "$MODDIR" -name '*.ko' | wc -l) .ko files, $(du -sh "$MODDIR" | cut -f1)"
    for name in usb-storage mmc_block sdhci rtsx_usb usbhid sr_mod isofs xhci-pci; do
        grep -aq "$name" "$MODDIR/modules.dep" || echo "    WARN: $name not in slim modules.dep"
    done
    # Generate the dependency-ordered load list for the shim: busybox-yb's
    # modprobe applet silently no-ops in this build (verified in QEMU: rc=0,
    # nothing reaches the kernel), so the shim insmods by explicit path
    # instead. Topological sort of modules.dep, deps first.
    LOADORDER="$MODDIR/loadorder"
    : > "$LOADORDER"
    declare -A MODDEPS=()
    while IFS=: read -r mp mdeps; do
        MODDEPS["$mp"]="$mdeps"
    done < "$MODDIR/modules.dep"
    remaining="$(cut -d: -f1 "$MODDIR/modules.dep")"
    done_list=" "
    progress=1
    while [ -n "${remaining// /}" ] && [ "$progress" = 1 ]; do
        progress=0
        left=""
        for m in $remaining; do
            ok=1
            for d in ${MODDEPS[$m]:-}; do
                case "$done_list" in *" $d "*) ;; *) ok=0; break ;; esac
            done
            if [ "$ok" = 1 ]; then
                printf '%s\n' "$m" >> "$LOADORDER"
                done_list="$done_list$m "
                progress=1
            else
                left="$left $m"
            fi
        done
        remaining="$left"
    done
    for m in $remaining; do printf '%s\n' "$m" >> "$LOADORDER"; done
    echo "    loadorder: $(wc -l < "$LOADORDER") modules"
fi

if [[ -n "$ASSETS" && -f "$ASSETS/busybox-yb" ]]; then
    echo ">>> Installing static busybox for the installer"
    # NAME MATTERS: busybox dispatches applets by argv[0] basename and only
    # accepts names starting with "busybox" (verified: 'yb-busybox' fails
    # EVERY call with 'applet not found', 'busybox-yb' works - 402 applets)
    install -m 0755 "$ASSETS/busybox-yb" "$WORK/initrd/sbin/busybox-yb"
fi

# CRITICAL: the stock Android-x86 initrd ships /bin/busybox but NO /bin/sh
# (its /init uses '#!/bin/busybox sh'). Our injected scripts use '#!/bin/sh',
# and if /bin/sh is missing the kernel exec fails ->
# "No working init found" -> instant kernel panic. Guarantee it exists.
echo ">>> Ensuring /bin/sh, /dev, /mnt exist in initrd"
mkdir -p "$WORK/initrd/bin" "$WORK/initrd/dev" "$WORK/initrd/mnt"
if [ ! -e "$WORK/initrd/bin/sh" ]; then
    if [ -e "$WORK/initrd/sbin/busybox-yb" ]; then
        # RELATIVE target: resolves to /sbin/busybox-yb once the initrd is
        # mounted as /, AND lets the build-time [ -e ] integrity gate below
        # verify it (an absolute /sbin/... link dangles inside the build tree).
        # argv[0] stays '/bin/sh' -> basename 'sh' is a valid applet -> OK.
        ln -s ../sbin/busybox-yb "$WORK/initrd/bin/sh"
    elif [ -e "$WORK/initrd/bin/busybox" ]; then
        ln -s busybox "$WORK/initrd/bin/sh"
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
BB=/sbin/busybox-yb
[ -x "$BB" ] || BB=/bin/busybox
[ -x "$BB" ] || { echo "[YB] no installer toolbox"; exit 0; }

# EVERY external command goes through the static toolbox $BB: the Android-x86
# initramfs ships NO standalone binaries (no /bin/mount, /bin/cp, /bin/cat...)
# and bare-name resolution depends on busybox applet fallback we cannot rely on.
CMD="$($BB cat /proc/cmdline 2>/dev/null)"
case "$CMD" in
    *YB_TARGET=sd*)   TARGET=sd ;;
    *YB_INSTALL=0*)   exit 0 ;;
    *)                TARGET=emmc ;;   # DEFAULT: erase eMMC, install Android
esac
# NOTE: /proc must STAY mounted here: busybox mount with no -t probes
# /proc/filesystems to auto-detect the fs type - unmounting /proc makes
# every later auto-detecting mount fail (this was the "cannot find boot
# media" bug even with /dev/sr0 present and iso9660 registered). The shim
# umounts /proc itself before exec'ing init.orig, so nothing to clean up.
# /sys/class/dmi/id (CONFIG_DMIID=y, built-in) is primary; if it is unreadable
# fall back to the kernel's own boot-log line ("DMI: Lenovo YB1-X91F ...").
# The destructive eMMC mode REQUIRES a positive match; without one nothing
# destructive ever runs (other machines boot this stick safely).
DMI="$($BB cat /sys/class/dmi/id/product_name 2>/dev/null)"
[ -n "$DMI" ] || DMI="$($BB cat /sys/class/dmi/id/board_name 2>/dev/null)"
if [ -z "$DMI" ]; then
    DMI="$($BB dmesg 2>/dev/null | $BB grep -aom1 'DMI:.*' | $BB head -c 100)"
fi
case "$DMI" in
    *YB1-X91F*|*YB1-X91L*|*YB1-X90F*|*YB1-X90L*) : ;;
    *)
        echo "[YB] not a Yoga Book (${DMI:-no DMI data}) - auto-install disabled for safety"
        echo "[YB]   product_name='$($BB cat /sys/class/dmi/id/product_name 2>&1)'"
        echo "[YB]   sys_vendor   ='$($BB cat /sys/class/dmi/id/sys_vendor 2>&1)'"
        echo "[YB]   board_name   ='$($BB cat /sys/class/dmi/id/board_name 2>&1)'"
        echo "[YB]   dmesg DMI: $($BB dmesg 2>/dev/null | $BB grep -aom1 'DMI:' || echo none)"
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

# ---- locate the BOOT MEDIA by content first (it is the USB stick) ----
# The YB1's Realtek card reader (0bda:07ef) presents inserted microSD cards as
# USB mass storage (/dev/sdX), so a card looks exactly like another stick:
# only the CONTENT (kernel + a system image: system.efs for Bliss 16 EROFS,
# or system.sfs/system.img for classic Android-x86) identifies the boot medium.
$BB mkdir -p /mnt/src
# Storage hosts probe asynchronously (ata/sdhci/usb load just before us), so
# /dev/sr0 can appear SECONDS after a one-shot scan has already given up -
# QEMU showed init.orig's own retry loop winning exactly that race. Poll for
# up to ~80s; on the Yoga Book the CD-ROM/USB stick appears within seconds.
SRCDEV=""
tries=0
while [ -z "$SRCDEV" ] && [ "$tries" -lt 40 ]; do
    for dev in /dev/sr[0-9] /dev/sd[a-z] /dev/sd[a-z][0-9] /dev/mmcblk[0-9] /dev/mmcblk[0-9]p[0-9]; do
        [ -b "$dev" ] || continue
        if $BB mount -o ro "$dev" /mnt/src 2>/dev/null; then
            if [ -f /mnt/src/kernel ] && { [ -f /mnt/src/system.efs ] || [ -f /mnt/src/system.sfs ] || [ -f /mnt/src/system.img ]; }; then
                SRCDEV="$dev"
                break
            fi
            $BB umount /mnt/src 2>/dev/null
        fi
    done
    if [ -n "$SRCDEV" ]; then break; fi
    tries=$((tries+1))
    $BB sleep 2
done
[ -n "$SRCDEV" ] || { echo "[YB] cannot find boot media"; exit 1; }
# whole-disk path of the boot medium (strip ONLY the partition suffix:
# sdb1->sdb, mmcblk0p2->mmcblk0; sr0 and whole mmcblkN/sdX stay whole - a sed
# 's/[0-9]*$//' would corrupt mmcblk0 into a nonexistent /dev/mmcblk and let
# the boot medium be picked as its own install target)
case "$SRCDEV" in
    /dev/sr[0-9])       SRCDISK="$SRCDEV" ;;
    /dev/mmcblk*p[0-9]) SRCDISK="${SRCDEV%p[0-9]}" ;;
    /dev/mmcblk[0-9])   SRCDISK="$SRCDEV" ;;
    /dev/sd[a-z][0-9])  SRCDISK="${SRCDEV%[0-9]}" ;;
    *)                  SRCDISK="$SRCDEV" ;;
esac
echo "[YB] boot media: $SRCDEV (disk $SRCDISK)"

# ---- pick the install target ----
# The old 'removable'-flag heuristic fails on the YB1: the Realtek card
# reader reports itself as NON-removable, so an inserted SD card looks like
# a second fixed disk and eMMC was never "unique" (field report: 32G card
# inserted -> count=2 -> abort). /sys/block/*/device/type is authoritative:
# real eMMC prints "MMC", SD cards print "SD", USB sticks "Direct-Access".
# Classify by type; keep the flag heuristic as fallback for QEMU/tests
# where no MMC-type device exists.
scan_targets() {
    TGT=""
    COUNT=0
    for d in /sys/block/*; do
        b="${d##*/}"
        case "$b" in
            loop*|ram*|sr*|md*|zram*|dm-*|nbd*|*rpmb*|mmcblk*boot*) continue ;;
        esac
        [ "/dev/$b" = "$SRCDISK" ] && continue
        if [ "$TARGET" = "emmc" ]; then
            [ "$($BB cat "$d/device/type" 2>/dev/null)" = "MMC" ] || continue
        else
            [ "$($BB cat "$d/device/type" 2>/dev/null)" = "SD" ] || continue
        fi
        TGT="/dev/$b"
        COUNT=$((COUNT+1))
    done
}
scan_targets_legacy() {
    TGT=""
    COUNT=0
    for d in /sys/block/*; do
        b="${d##*/}"
        case "$b" in
            loop*|ram*|sr*|md*|zram*|dm-*|nbd*|*rpmb*|mmcblk*boot*) continue ;;
        esac
        [ "$($BB cat "$d/removable" 2>/dev/null)" = "$WANT_REMOVABLE" ] || continue
        [ "/dev/$b" = "$SRCDISK" ] && continue
        TGT="/dev/$b"
        COUNT=$((COUNT+1))
    done
}
TGT=""
tries=0
while [ "$tries" -lt 20 ]; do
    scan_targets
    if [ "$COUNT" -ge 1 ]; then break; fi
    # no type-matched device yet - maybe hosts are still probing; retry
    tries=$((tries+1))
    $BB sleep 2
done
if [ "$COUNT" -ne 1 ]; then
    # fallback: legacy removable-flag heuristic (QEMU disks, odd hosts)
    scan_targets_legacy
fi
if [ "$TARGET" = "emmc" ]; then
    if [ "$COUNT" = "1" ] && [ -n "$TGT" ]; then :;
    elif [ "$COUNT" -gt 1 ]; then
        echo "[YB] multiple MMC disks found (count=$COUNT) - remove the inserted SD card and reboot"; exit 0
    else
        echo "[YB] no eMMC (MMC-type disk) found - aborting"; exit 0
    fi
else
    [ "$COUNT" = "1" ] && [ -n "$TGT" ] || {
        echo "[YB] no removable SD card found (count=$COUNT, boot stick=$SRCDISK) - insert one and reboot"
        exit 0
    }
fi
# partition suffix: mmcblk0p1 vs sda1
case "$TGT" in
    *mmcblk*|*mmc*) P1="${TGT}p1"; P2="${TGT}p2" ;;
    *)              P1="${TGT}1";  P2="${TGT}2"  ;;
esac
echo "[YB] target device: $TGT"

# refuse to install onto the medium we are booting from
case "$TGT" in
    "$SRCDISK") echo "[YB] target == boot media - refusing"; exit 1 ;;
esac

if [ "$TARGET" != "emmc" ]; then
    SIZE="$($BB blockdev --getsize64 "$TGT" 2>/dev/null || echo 0)"
    if [ "$SIZE" -lt 4000000000 ] 2>/dev/null; then
        echo "[YB] SD card too small (<4GB) - aborting"; exit 1
    fi
fi

echo "!!!! AUTO-INSTALL: erasing $TGT in 10 seconds — POWER OFF NOW TO ABORT !!!!"
$BB sleep 10

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
$BB blockdev --rereadpt "$TGT" 2>/dev/null || true
$BB sleep 1
$BB mkdosfs -n ANDROID "$P1"
# busybox mke2fs has NO -t option (it fails with usage text!) and writes an
# ext2 filesystem - which the Yoga-Book kernel mounts fine through its ext4
# driver (CONFIG_EXT4_USE_FOR_EXT2=y, no standalone EXT2_FS).
$BB mke2fs -F -L DATA "$P2"

# ---- stage files ----
$BB mkdir -p /mnt/efi /mnt/data
$BB mount "$P1" /mnt/efi || { echo "[YB] ESP mount failed"; exit 1; }
# kernel + initrd are small and live on the ESP; the multi-GB system image
# cannot fit a 256M ESP, so it is staged on the DATA partition (classic
# Android-x86 layout: the boot entries pass SRC=/and-yb so init.orig finds
# $SRC/system.efs there; Bliss 16 ships EROFS, erofs.ko is in the initrd)
$BB cp /mnt/src/kernel /mnt/src/initrd.img /mnt/efi/
$BB mount "$P2" /mnt/data || { echo "[YB] DATA mount failed"; exit 1; }
$BB mkdir -p /mnt/data/and-yb
for f in /mnt/src/ramdisk.img /mnt/src/system.efs /mnt/src/system.sfs /mnt/src/system.img; do
    [ -f "$f" ] && $BB cp "$f" /mnt/data/and-yb/
done
# integrity gates: never report COMPLETE unless the essentials really landed
[ -f /mnt/efi/kernel ] && [ -f /mnt/efi/initrd.img ] || { echo "[YB] kernel/initrd copy failed"; exit 1; }
[ -f /mnt/data/and-yb/system.efs ] || [ -f /mnt/data/and-yb/system.sfs ] || [ -f /mnt/data/and-yb/system.img ] || { echo "[YB] system image copy failed"; exit 1; }

# source dir is 'efi/boot' (lowercase) on the ISO — match any case
ESPBOOT=""
for cand in /mnt/src/EFI/BOOT /mnt/src/efi/boot /mnt/src/efi/BOOT /mnt/src/EFI/boot; do
    [ -d "$cand" ] && ESPBOOT="$cand" && break
done
if [ -n "$ESPBOOT" ]; then
    $BB mkdir -p /mnt/efi/EFI/BOOT
    $BB cp -r "$ESPBOOT/." /mnt/efi/EFI/BOOT/
fi

$BB cat > /mnt/efi/EFI/BOOT/grub.cfg <<GRUB
set timeout=1
set default=0
menuentry "Android (Bass OS 16.9.7) - installed on eMMC" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive SRC=/and-yb DATA=$P2
    initrd /initrd.img
}
menuentry "Android - installed on eMMC, SAFE GRAPHICS (try this if boot panics/hangs)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive SRC=/and-yb DATA=$P2 nomodeset
    initrd /initrd.img
}
menuentry "Reinstall to SD card (keeps this eMMC install)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive SRC=/and-yb YB_TARGET=sd
    initrd /initrd.img
}
GRUB
# the firmware-loaded GRUB sources android.cfg next to BOOTX64.EFI - our
# menu must live THERE or the stock Bliss menu takes over (or nothing boots)
if [ -f /mnt/efi/EFI/BOOT/android.cfg ]; then
    $BB mv /mnt/efi/EFI/BOOT/android.cfg /mnt/efi/EFI/BOOT/android.cfg.bliss
fi
$BB cp /mnt/efi/EFI/BOOT/grub.cfg /mnt/efi/EFI/BOOT/android.cfg
# some firmwares read /EFI/BOOT/grub/grub.cfg instead
$BB mkdir -p /mnt/efi/EFI/BOOT/grub 2>/dev/null || true
$BB cp /mnt/efi/EFI/BOOT/grub.cfg /mnt/efi/EFI/BOOT/grub/grub.cfg 2>/dev/null || true
$BB umount /mnt/efi
$BB umount /mnt/data 2>/dev/null

$BB sync
if [ "$TARGET" = "emmc" ]; then
    echo "[YB] AUTO-INSTALL COMPLETE (eMMC wiped, Android installed) - powering off"
else
    echo "[YB] AUTO-INSTALL COMPLETE (SD card ready) - remove USB stick; keep SD in"
    echo "[YB] Power on and pick the SD entry in the Volume-Up boot menu."
fi
$BB sleep 2
$BB poweroff -f
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
# Every external command goes through the static toolbox: the initramfs has
# no standalone binaries, so bare names are a gamble.
BB=/sbin/busybox-yb
[ -x "$BB" ] || BB=/bin/busybox
PATH=/sbin:/bin:/usr/sbin:/usr/bin; export PATH
$BB mount -t proc proc /proc 2>/dev/null
$BB mount -t sysfs sysfs /sys 2>/dev/null
$BB mount -t devtmpfs devtmpfs /dev 2>/dev/null
# Our Yoga Book kernel builds USB storage, SD/eMMC hosts and HID as MODULES,
# and nothing else in this initrd loads them: without this, neither the
# installer nor Android's init ever see any disk.
echo "[YB] loading storage/SD/HID modules..."
# busybox-yb's modprobe silently no-ops (rc=0, no insmod reaches the kernel,
# verified in QEMU) - load by explicit path in dependency order instead.
# loadorder is generated at build time from modules.dep (deps first).
# Fallback for fat-initrd builds (YB_SLIM_INITRD=0): name-based modprobe loop.
KREL=$($BB uname -r)
if [ -s "/lib/modules/$KREL/loadorder" ]; then
    for m in $($BB cat "/lib/modules/$KREL/loadorder"); do
        $BB insmod "/lib/modules/$KREL/$m" 2>/dev/null || true
    done
else
    for m in usb-storage uas mmc_block sdhci sdhci-pci sdhci-acpi usbhid hid-generic hid \
             rtsx_usb rtsx_usb_sdmmc rtsx_pci rtsx_pci_sdmmc \
             sd_mod sr_mod ata_piix ahci nvme virtio_blk virtio_pci \
             isofs udf vfat fat nls_cp437 nls_ascii nls_base nls_iso8859-1 erofs ext4; do
        $BB modprobe "$m" 2>/dev/null || true
    done
fi
$BB sleep 3
if ! $BB grep -qE 'YB_INSTALL=0|DATA=' /proc/cmdline 2>/dev/null; then
    echo "[YB] auto-installer starting (pass YB_INSTALL=0 to skip)..."
    /sbin/yogabook-autostall || { echo "[YB] installer did not run - continuing to live boot"; }
fi
$BB umount /proc 2>/dev/null
if [ -x /init.orig ]; then
    exec /init.orig
elif [ -x /sbin/init ]; then
    exec /sbin/init
fi
exec $BB sh
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
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive YB_TARGET=sd
    initrd /initrd.img
}
menuentry "Yoga Book - Live boot (no install)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive YB_INSTALL=0
    initrd /initrd.img
}
menuentry "Yoga Book - Live boot, SAFE GRAPHICS (try this if boot panics/hangs)" {
    search --no-floppy --file /kernel --set=root
    linux /kernel root=/dev/ram0 androidboot.hardware=android_x86_64 androidboot.selinux=permissive YB_INSTALL=0 nomodeset
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
