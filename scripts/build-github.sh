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
# Base Android x86 boot harness (verified official x86_64 live ISO with working initrd + system.sfs)
BOOT_HARNESS_URL="${BOOT_HARNESS_URL:-https://downloads.sourceforge.net/project/android-x86/Release%209.0/android-x86_64-9.0-r2.iso}"

# Optional custom system image (e.g. LineageOS GSI or Bliss OS x86_64)
# If empty, the verified native x86_64 system from the base harness is used.
LINEAGE_GSI_URL="${LINEAGE_GSI_URL:-}"

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
mkdir -p "$FW_STAGE" "$WORK/firmware-stage/intel/sof-tplg"

# Download SOF release binaries (contains sof-cht-rt5677.tplg)
if curl -f -sL --retry 3 --max-time 180 -o "$WORK/sof-bin.tar.gz" \
  "https://github.com/thesofproject/sof-bin/releases/download/$SOF_TAG/sof-bin-$SOF_VER.tar.gz"; then
  tar -xzf "$WORK/sof-bin.tar.gz" -C "$WORK" 2>/dev/null || true
  cp -a "$WORK/sof-bin-$SOF_VER"/sof/v*/* "$FW_STAGE/" 2>/dev/null || true
  cp -a "$WORK/sof-bin-$SOF_VER"/sof-tplg-v*/* "$WORK/firmware-stage/intel/sof-tplg/" 2>/dev/null || true
fi

# Fetch Maurizio Casciano's tested Yoga Book cht-rt5677 topology
curl -f -sL --retry 3 --max-time 60 -o "$FW_STAGE/sof-cht-rt5677.tplg" \
  "https://raw.githubusercontent.com/Yoga-Book/Yoga-Book-Sound-Open-Firmware/submission/cht-rt5677-topology2-ipc3-v1/tools/topology/topology2/production/sof-cht-rt5677.tplg" 2>/dev/null || true
cp -f "$FW_STAGE/sof-cht-rt5677.tplg" "$WORK/firmware-stage/intel/sof-tplg/" 2>/dev/null || true
cp -f "$FW_STAGE/sof-cht-rt5677.tplg" "$WORK/firmware-stage/" 2>/dev/null || true

# ---------------------------------------------------------------- 4. Prepare Base Android x86 System
say "Preparing Base Android x86 System & Boot Harness"
BASE_STAGE="$WORK/android-base"
mkdir -p "$BASE_STAGE"

# Fetch boot harness for initrd.img and live boot scripts
if [ ! -f "$WORK/boot_harness.iso" ]; then
  say "Fetching Android x86 live boot harness ($BOOT_HARNESS_URL)"
  curl -f -L --retry 3 --max-time 600 -o "$WORK/boot_harness.iso" "$BOOT_HARNESS_URL"
  7z x "$WORK/boot_harness.iso" -o"$BASE_STAGE" -y 2>/dev/null || true
fi

# Fetch custom system image if specified
if [ -n "$LINEAGE_GSI_URL" ]; then
  say "Fetching custom System Image ($LINEAGE_GSI_URL)"
  curl -f -L --retry 3 --max-time 600 -o "$WORK/custom_system.archive" "$LINEAGE_GSI_URL"
  7z x "$WORK/custom_system.archive" -o"$BASE_STAGE" -y 2>/dev/null || true
  SYS_RAW=$(find "$BASE_STAGE" -maxdepth 2 -name "*.img" ! -name "initrd.img" ! -name "install.img" ! -name "ramdisk.img" | head -1)
  if [ -n "$SYS_RAW" ] && [ "$SYS_RAW" != "$BASE_STAGE/system.img" ]; then
    mv -v "$SYS_RAW" "$BASE_STAGE/system.img"
  fi
  if [ -f "$BASE_STAGE/system.img" ]; then
    rm -f "$BASE_STAGE/system.sfs"
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
if [ -f "$BASE_STAGE/system.img" ]; then
  cp -v "$BASE_STAGE/system.img" "$STAGE/ANDRID/"
elif [ -f "$BASE_STAGE/system.sfs" ]; then
  cp -v "$BASE_STAGE/system.sfs" "$STAGE/ANDRID/"
fi
for f in gearlock install.img ramdisk.img; do
  if [ -f "$BASE_STAGE/$f" ]; then
    cp -v "$BASE_STAGE/$f" "$STAGE/ANDRID/"
  fi
done

# Integrate custom modules into initrd
say "Repacking initrd with Yoga Book modules and Halo Keyboard files"
export RDK_WORK="$WORK/rdk_work"
rm -rf "$RDK_WORK"
mkdir -p "$RDK_WORK"

if [ -f "$BASE_STAGE/initrd.img" ]; then
  (cd "$RDK_WORK" && (gzip -dc "$BASE_STAGE/initrd.img" 2>/dev/null || xz -dc "$BASE_STAGE/initrd.img" 2>/dev/null || cat "$BASE_STAGE/initrd.img") | cpio -idmv 2>/dev/null || true)
fi

# Overlay our modules and firmware
mkdir -p "$RDK_WORK/lib/modules" "$RDK_WORK/lib/firmware/intel/sof" "$RDK_WORK/lib/firmware/intel/sof-tplg"
cp -a "$MOD_STAGE/lib/modules/." "$RDK_WORK/lib/modules/" 2>/dev/null || true
cp -a "$WORK/firmware-stage/." "$RDK_WORK/lib/firmware/" 2>/dev/null || true

# Overlay Halo keyboard binary, script and config
mkdir -p "$RDK_WORK/system/bin" "$RDK_WORK/system/etc/touch_keyboard" \
         "$RDK_WORK/vendor/bin" "$RDK_WORK/vendor/etc/touch_keyboard" \
         "$RDK_WORK/bin" "$RDK_WORK/etc/touch_keyboard"

cp -v "$WORK/touch_keyboard_handler" "$RDK_WORK/system/bin/" 2>/dev/null || true
cp -v "$WORK/touch_keyboard_handler" "$RDK_WORK/vendor/bin/" 2>/dev/null || true
cp -v "$WORK/touch_keyboard_handler" "$RDK_WORK/bin/" 2>/dev/null || true

cp -v "$HERE/device/yogabook/halo-keyboard/halo-keyboard-start.sh" "$RDK_WORK/system/bin/" 2>/dev/null || true
cp -v "$HERE/device/yogabook/halo-keyboard/halo-keyboard-start.sh" "$RDK_WORK/vendor/bin/" 2>/dev/null || true
chmod +x "$RDK_WORK"/system/bin/* "$RDK_WORK"/vendor/bin/* "$RDK_WORK"/bin/* 2>/dev/null || true

cp -a "$HERE/device/yogabook/halo-keyboard/config/." "$RDK_WORK/system/etc/touch_keyboard/" 2>/dev/null || true
cp -a "$HERE/device/yogabook/halo-keyboard/config/." "$RDK_WORK/vendor/etc/touch_keyboard/" 2>/dev/null || true
cp -a "$HERE/device/yogabook/halo-keyboard/config/." "$RDK_WORK/etc/touch_keyboard/" 2>/dev/null || true

# Copy Yoga Book diagnostics and log capture tool
mkdir -p "$RDK_WORK/scripts"
cp -v "$HERE/device/yogabook/diagnostics/yablog.sh" "$RDK_WORK/bin/" 2>/dev/null || true
cp -v "$HERE/device/yogabook/diagnostics/yablog.sh" "$RDK_WORK/system/bin/" 2>/dev/null || true
cp -v "$HERE/device/yogabook/diagnostics/yablog.sh" "$RDK_WORK/vendor/bin/" 2>/dev/null || true
chmod +x "$RDK_WORK"/bin/yablog.sh "$RDK_WORK"/system/bin/yablog.sh "$RDK_WORK"/vendor/bin/yablog.sh 2>/dev/null || true

# Early boot & harddisk detection script in initrd
cat > "$RDK_WORK/scripts/yogabook-disk-detect.sh" <<'EOF'
#!/bin/busybox sh
# Realtime storage scan & boot log capture for Yoga Book flashable media

echo ">>> [YOGABOOK] Hardware & Storage Controller Probing..."
sleep 1

# List storage devices
echo ">>> [STORAGE DETECTION]:"
for b in /sys/class/block/*; do
    [ -d "$b" ] || continue
    bn="${b##*/}"
    case "$bn" in loop*|ram*) continue ;; esac
    sz=$(cat "$b/size" 2>/dev/null || echo 0)
    mb=$(( sz * 512 / 1024 / 1024 ))
    rem=$(cat "$b/removable" 2>/dev/null || echo "?")
    mod=$(cat "$b/device/name" 2>/dev/null || cat "$b/device/model" 2>/dev/null || echo "Storage")
    echo "    /dev/$bn: $mod (${mb} MB, removable=$rem)"
done

# Ensure all block devices in sysfs have nodes in /dev
for b in /sys/class/block/*; do
    [ -d "$b" ] || continue
    bn="${b##*/}"
    case "$bn" in loop*|ram*) continue ;; esac
    if [ ! -b "/dev/$bn" ] && [ -f "$b/dev" ]; then
        dev_num=$(cat "$b/dev" 2>/dev/null)
        if [ -n "$dev_num" ]; then
            major=${dev_num%:*}
            minor=${dev_num#*:}
            mknod "/dev/$bn" b "$major" "$minor" 2>/dev/null
            mkdir -p /dev/block
            ln -sf "/dev/$bn" "/dev/block/$bn" 2>/dev/null
        fi
    fi
done

# Try locating bootlogs on any mounted partition or attempt mounting boot media
LOG_DIR=""
for m in $(awk '{print $2}' /proc/mounts 2>/dev/null); do
    if [ -d "$m/bootlogs" ] && touch "$m/bootlogs/.t" 2>/dev/null; then
        rm -f "$m/bootlogs/.t"
        LOG_DIR="$m/bootlogs"
        break
    fi
done

if [ -z "$LOG_DIR" ]; then
    mkdir -p /mnt_log
    for p in /dev/mmcblk*p* /dev/mmcblk[0-9] /dev/sd*[0-9] /dev/sd[a-z]; do
        [ -b "$p" ] || continue
        mount -t vfat "$p" /mnt_log 2>/dev/null || mount "$p" /mnt_log 2>/dev/null || continue
        if [ -d "/mnt_log/bootlogs" ] || [ -d "/mnt_log/ANDRID" ]; then
            mkdir -p /mnt_log/bootlogs 2>/dev/null
            if touch /mnt_log/bootlogs/.t 2>/dev/null; then
                rm -f /mnt_log/bootlogs/.t
                LOG_DIR="/mnt_log/bootlogs"
                echo ">>> [LOGGING] Attached boot media log destination: $p -> $LOG_DIR"
                break
            fi
        fi
        umount /mnt_log 2>/dev/null || true
    done
fi

if [ -n "$LOG_DIR" ]; then
    TS=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "early")
    OUT_FILE="$LOG_DIR/harddisk-detection-$TS.txt"
    {
        echo "=== Yoga Book Storage & Hardware Enumeration ($TS) ==="
        echo "--- cmdline ---"
        cat /proc/cmdline
        echo "--- DMI ---"
        for d in product_name product_version sys_vendor board_name bios_version; do
            echo "$d: $(cat /sys/class/dmi/id/$d 2>/dev/null)"
        done
        echo "--- /proc/partitions ---"
        cat /proc/partitions
        echo "--- Discovered Disks ---"
        for b in /sys/class/block/*; do
            [ -d "$b" ] || continue
            bn="${b##*/}"
            echo "Device: $bn (size: $(cat "$b/size" 2>/dev/null), removable: $(cat "$b/removable" 2>/dev/null), model: $(cat "$b/device/name" 2>/dev/null || cat "$b/device/model" 2>/dev/null))"
        done
        echo "--- Kernel dmesg (MMC & storage events) ---"
        dmesg | grep -iE 'mmc|sdhci|sdio|scsi|ata|usb|block'
        echo "--- Full Kernel dmesg ---"
        dmesg
    } > "$OUT_FILE" 2>&1
    cp -f "$OUT_FILE" "$LOG_DIR/harddisk-detection-latest.txt" 2>/dev/null || true
    echo ">>> [LOGGING] Boot & harddisk detection log captured to $OUT_FILE"
    ( dmesg -w >> "$LOG_DIR/dmesg.log" 2>/dev/null ) &
fi
EOF
chmod +x "$RDK_WORK/scripts/yogabook-disk-detect.sh"

# Hook detection and robust mounting into initrd init
if [ -f "$RDK_WORK/init" ]; then
  python3 - "$RDK_WORK/init" <<'PYEOF'
import sys, os
init_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("RDK_WORK", ""), "init")
with open(init_path, "r", encoding="latin1") as f:
    c = f.read()

# 1. Place yogabook-disk-detect after cttyhack
anchor = 'exec env HAS_CTTY=Yes setsid cttyhack /bin/sh "$0" "$@"\nfi'
if anchor in c and "/scripts/yogabook-disk-detect.sh" not in c:
    c = c.replace(anchor, anchor + '\n\n[ -x /scripts/yogabook-disk-detect.sh ] && /scripts/yogabook-disk-detect.sh\n')

# 2. Patch try_mount to direct-mount vfat/ext4/iso9660 without failing on blkid
old_try_mount = """try_mount()
{
	RW=$1; shift
	if [ "${ROOT#*:/}" != "$ROOT" ]; then
		# for NFS roots, use nolock to avoid dependency to portmapper
		mount -o $RW,noatime,nolock $@
		return $?
	fi
	case $(blkid $1) in
		*TYPE=*ntfs*)
			mount.ntfs-3g -o rw,force $@
			;;
		*TYPE=*)
			mount -o $RW,noatime $@
			;;
		*)
			return 1
			;;
	esac
}"""

new_try_mount = """try_mount()
{
	RW=$1; shift
	dev=$1
	target=$2
	mkdir -p "$target"
	mount -o $RW,noatime "$dev" "$target" 2>/dev/null && return 0
	mount -t vfat -o $RW,noatime,check=relaxed,utf8 "$dev" "$target" 2>/dev/null && return 0
	mount -t vfat -o $RW,noatime "$dev" "$target" 2>/dev/null && return 0
	mount -t ext4 -o $RW,noatime "$dev" "$target" 2>/dev/null && return 0
	mount -t iso9660 -o $RW,noatime "$dev" "$target" 2>/dev/null && return 0
	mount.ntfs-3g -o rw,force "$dev" "$target" 2>/dev/null && return 0
	return 1
}"""
c = c.replace(old_try_mount, new_try_mount)

# 3. Fix check_root to never mangle device paths
old_check_root_dev = """	if [ "`dirname $1`" = "/dev" ]; then
		[ -e $1 ] || return 1
		blk=`basename $1`
		[ ! -e /dev/block/$blk ] && ln $1 /dev/block
		dev=/dev/block/$blk
	else
		dev=$1
	fi"""

new_check_root_dev = """	dev=$1
	[ -e "$dev" ] || return 1
	blk=$(basename "$dev")
	mkdir -p /dev/block
	[ ! -e "/dev/block/$blk" ] && ln -sf "$dev" "/dev/block/$blk" 2>/dev/null"""
c = c.replace(old_check_root_dev, new_check_root_dev)

# 4. Parse SRC= from cmdline
old_cmdline = """for c in `cat /proc/cmdline`; do
	case $c in
		iso-scan/filename=*)
			SRC=iso
			eval `echo $c | cut -b1-3,18-`
			;;
		*)
			;;
	esac
done"""

new_cmdline = """for c in `cat /proc/cmdline`; do
	case $c in
		SRC=*)
			eval $c
			;;
		src=*)
			eval $c
			;;
		iso-scan/filename=*)
			SRC=iso
			eval `echo $c | cut -b1-3,18-`
			;;
		*)
			;;
	esac
done

SRC=$(echo "$SRC" | sed 's|^/*||;s|/*$||')"""
c = c.replace(old_cmdline, new_cmdline)

# 5. Auto-detect directory containing ramdisk.img
old_ramdisk = """	if [ -e /mnt/$SRC/$RAMDISK ]; then
		zcat /mnt/$SRC/$RAMDISK | cpio -id > /dev/null
	elif [ -b /dev/$RAMDISK ]; then
		zcat /dev/$RAMDISK | cpio -id > /dev/null
	else
		return 1
	fi"""

new_ramdisk = """	if [ -z "$SRC" ] || [ ! -e "/mnt/$SRC/$RAMDISK" ]; then
		for candidate in ANDRID andrid android Android ANDROID ""; do
			if [ -n "$candidate" ] && [ -e "/mnt/$candidate/$RAMDISK" ]; then
				SRC="$candidate"
				break
			elif [ -z "$candidate" ] && [ -e "/mnt/$RAMDISK" ]; then
				SRC=""
				break
			fi
		done
	fi

	if [ -n "$SRC" ] && [ -e "/mnt/$SRC/$RAMDISK" ]; then
		zcat "/mnt/$SRC/$RAMDISK" | cpio -id > /dev/null
	elif [ -e "/mnt/$RAMDISK" ]; then
		zcat "/mnt/$RAMDISK" | cpio -id > /dev/null
	elif [ -b "/dev/$RAMDISK" ]; then
		zcat "/dev/$RAMDISK" | cpio -id > /dev/null
	else
		return 1
	fi"""
c = c.replace(old_ramdisk, new_ramdisk)

# 6. Dynamically synthesize block device nodes from /sys/class/block in the detection loop
old_loop = """while :; do
	for device in ${ROOT:-/dev/[hmnsv][dmrv][0-9a-z]*}; do
		check_root $device && break 2
		mountpoint -q /mnt && umount /mnt
	done
	sleep 1
	echo -n .
done"""

new_loop = """while :; do
	for b in /sys/class/block/*; do
		[ -d "$b" ] || continue
		bn="${b##*/}"
		case "$bn" in loop*|ram*) continue ;; esac
		if [ ! -b "/dev/$bn" ] && [ -f "$b/dev" ]; then
			dev_num=$(cat "$b/dev" 2>/dev/null)
			if [ -n "$dev_num" ]; then
				major=${dev_num%:*}
				minor=${dev_num#*:}
				mknod "/dev/$bn" b "$major" "$minor" 2>/dev/null
				mkdir -p /dev/block
				ln -sf "/dev/$bn" "/dev/block/$bn" 2>/dev/null
			fi
		fi
	done
	mdev -s 2>/dev/null

	for device in ${ROOT:-/dev/[hmnsv][dmrv][0-9a-z]*}; do
		check_root $device && break 2
		mountpoint -q /mnt && umount /mnt
	done
	sleep 1
	echo -n .
done"""
c = c.replace(old_loop, new_loop)

# 7. Early devtmpfs mount if supported
old_mounts = """	busybox mount -t proc proc /proc
	busybox mount -t sysfs sys /sys"""
new_mounts = """	busybox mount -t proc proc /proc
	busybox mount -t sysfs sys /sys
	busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null || true"""
c = c.replace(old_mounts, new_mounts)

with open(init_path, "w", encoding="latin1") as f:
    f.write(c)
PYEOF
  chmod +x "$RDK_WORK/init"
fi

# Repack initrd.img
(cd "$RDK_WORK" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$STAGE/ANDRID/initrd.img")

# ---------------------------------------------------------------- 6. Setup GRUB EFI Bootloader
say "Building GRUB EFI Bootloader (BOOTX64.EFI & BOOTIA32.EFI)"
cat > "$WORK/grub-standalone-efi.cfg" <<'EOF'
set echo=1
set timeout=5
set default=0

# Search for configuration across filesystems
if [ -z "$root" ] || [ ! -f "($root)/boot/grub/grub.cfg" ]; then
    search --no-floppy --file --set=root /boot/grub/grub.cfg
fi
if [ -z "$root" ]; then
    search --no-floppy --label --set=root YOGABOOK
fi
if [ -z "$root" ]; then
    search --no-floppy --file --set=root /ANDRID/kernel
fi

set prefix=($root)/boot/grub
if [ -f "$prefix/grub.cfg" ]; then
    configfile "$prefix/grub.cfg"
elif [ -f "($root)/ANDRID/kernel" ]; then
    menuentry "Direct Fallback Boot" {
        set gfxpayload=keep
        linux ($root)/ANDRID/kernel androidboot.hardware=android_x86 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID quiet
        initrd ($root)/ANDRID/initrd.img
    }
fi
EOF

EFI_MODS="fat iso9660 ext2 part_gpt part_msdos normal linux configfile search search_fs_file search_fs_uuid search_label minicmd gzio reboot halt sleep cat echo ls test true help all_video efi_gop efi_uga gfxterm font loadenv"

mkdir -p "$STAGE/EFI/BOOT"

say "Building 64-bit GRUB EFI (BOOTX64.EFI)"
grub-mkimage -O x86_64-efi -o "$STAGE/EFI/BOOT/BOOTX64.EFI" \
  --config="$WORK/grub-standalone-efi.cfg" -p '/boot/grub' \
  $EFI_MODS

say "Building 32-bit GRUB EFI (BOOTIA32.EFI) for Cherry Trail mixed-mode/32-bit UEFI"
if [ -d /usr/lib/grub/i386-efi ]; then
  grub-mkimage -O i386-efi -o "$STAGE/EFI/BOOT/BOOTIA32.EFI" \
    --config="$WORK/grub-standalone-efi.cfg" -p '/boot/grub' \
    $EFI_MODS || true
fi

# Copy unicode font for gfxterm if available
mkdir -p "$STAGE/boot/grub/fonts"
for f in /usr/share/grub/unicode.pf2 /boot/grub/fonts/unicode.pf2; do
  if [ -f "$f" ]; then
    cp -v "$f" "$STAGE/boot/grub/fonts/"
    break
  fi
done

CMDLINE="androidboot.hardware=android_x86 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID"

if [ -n "$LINEAGE_GSI_URL" ]; then
  OS_TITLE="Yoga Book LineageOS $LINEAGE_VER (x86_64)"
  ISO_NAME="YOGABOOK-LineageOS-$LINEAGE_VER-x86_64-$(date +%Y%m%d)-live.iso"
else
  OS_TITLE="Yoga Book Android-x86 Live (x86_64)"
  ISO_NAME="YOGABOOK-Android-x86_64-$(date +%Y%m%d)-live.iso"
fi

cat > "$STAGE/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0

loadfont unicode || true
set gfxmode=auto
set gfxpayload=keep
terminal_output gfxterm console || true

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "$OS_TITLE - Standard" {
    set gfxpayload=keep
    echo "Loading Yoga Book Kernel..."
    linux /ANDRID/kernel $CMDLINE quiet
    echo "Loading Initrd..."
    initrd /ANDRID/initrd.img
}

menuentry "$OS_TITLE - Verbose Console" {
    set gfxpayload=keep
    echo "Loading Yoga Book Kernel in Verbose Mode..."
    linux /ANDRID/kernel $CMDLINE console=tty0 DEBUG=2
    echo "Loading Initrd..."
    initrd /ANDRID/initrd.img
}

menuentry "$OS_TITLE - Safe Graphics (nomodeset)" {
    set gfxpayload=keep
    echo "Loading Yoga Book Kernel (nomodeset)..."
    linux /ANDRID/kernel $CMDLINE nomodeset console=tty0 DEBUG=1
    initrd /ANDRID/initrd.img
}

menuentry "$OS_TITLE - Text Payload" {
    set gfxpayload=text
    echo "Loading Yoga Book Kernel (text payload)..."
    linux /ANDRID/kernel $CMDLINE console=tty0
    echo "Loading Initrd..."
    initrd /ANDRID/initrd.img
}

menuentry "Reboot System" {
    reboot
}

menuentry "Power Off" {
    halt
}
EOF

# ---------------------------------------------------------------- 7. Create Hybrid ISO
say "Generating Hybrid ISO with make-refind-iso.sh"
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

