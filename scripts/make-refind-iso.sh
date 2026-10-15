#!/usr/bin/env bash
# Build the Yoga Book hybrid boot ISO:
#
#   * Partition/filesystem layout mirrors android-x86 style media:
#     a large FAT32 partition holds EVERYTHING (rEFInd, kernels, ramdisks,
#     system images, empty bootlogs/ dir) so rEFInd can read its own files
#     (rEFInd has no ISO9660 driver).
#   * UEFI x86_64  -> EFI/BOOT/BOOTX64.EFI = rEFInd (touch UI)
#   * Legacy BIOS  -> GRUB i386-pc via El Torito (reads the FAT partition)
#   * Hybrid MBR/GPT so the same image boots from USB sticks and SD cards.
#
# Usage:
#   make-refind-iso.sh -o out.iso -a ANDROID_DIR -f files... [-e extra_dir ...]
#
#   -o  output iso path
#   -a  name of the android dir inside the media (e.g. ANDRID)
#   -f  file to copy into the android dir (repeatable): kernel,
#       ramdisk-all-combined.img, system.img, ... (symlinks dereferenced)
#   -e  extra directory to merge into the media root (e.g. staging with
#       refind/, EFI/, boot/, kernels/)
#   -s  FAT image size (default: computed + 512M headroom)
set -euo pipefail

OUT="" ANDROID_DIR="ANDRID" SIZE="" 
FILES=() EXTRAS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2 ;;
    -a) ANDROID_DIR="$2"; shift 2 ;;
    -f) FILES+=("$(readlink -f "$2")"); shift 2 ;;
    -e) EXTRAS+=("$(readlink -f "$2")"); shift 2 ;;
    -s) SIZE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$OUT" ] || { echo "ERROR: -o required" >&2; exit 2; }
command -v xorriso mformat mcopy grub-mkimage >/dev/null || {
  echo "ERROR: need xorriso, mtools (mformat/mcopy), grub-pc-bin (grub-mkimage)" >&2; exit 2; }

WORK="$(mktemp -d /tmp/ybiso.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- staging tree
STAGE="$WORK/fat"
mkdir -p "$STAGE/$ANDROID_DIR" "$STAGE/bootlogs"

# android boot files (kernel, ramdisk, images) - dereference symlinks
for f in "${FILES[@]}"; do
  cp -L "$f" "$STAGE/$ANDROID_DIR/"
done

# extra trees: refind/, EFI/, boot/grub, kernels/, ...
for e in "${EXTRAS[@]}"; do
  cp -a "$e"/. "$STAGE/"
done

[ -f "$STAGE/EFI/BOOT/BOOTX64.EFI" ] || {
  echo "ERROR: staged tree lacks EFI/BOOT/BOOTX64.EFI"; exit 1; }
touch "$STAGE/EFI/BOOT/refind.conf"

# ---------------------------------------------------------------- FAT32 image
used_kb=$(du -sk "$STAGE" | awk '{print $1}')
if [ -z "$SIZE" ]; then
  SIZE_MB=$(( used_kb / 1024 + 768 ))
  [ "$SIZE_MB" -lt 1024 ] && SIZE_MB=1024
  SIZE="${SIZE_MB}M"
fi
echo "FAT image size: $SIZE (staged ${used_kb} kB)"
truncate -s "$SIZE" "$WORK/fat.img"
mformat -i "$WORK/fat.img" -F -v YOGABOOK ::
mcopy -i "$WORK/fat.img" -s "$STAGE"/* ::/

# ---------------------------------------------------------------- BIOS GRUB bits
GRUB_LIB="$(dirname "$(command -v grub-mkimage)")/../lib/grub/i386-pc"
[ -d "$GRUB_LIB" ] || GRUB_LIB=/usr/lib/grub/i386-pc
[ -d "$GRUB_LIB" ] || { echo "ERROR: grub i386-pc modules not found (apt install grub-pc-bin)"; exit 2; }

ALL_MODS="biosdisk iso9660 fat part_msdos part_gpt normal linux configfile search search_fs_file search_fs_uuid search_label minicmd gzio reboot halt sleep cat echo ls test true help png play envfile loopback all_video gfxterm gettext font"
# keep only modules that exist in this grub build
MODS=""
for m in $ALL_MODS; do
  [ -f "$GRUB_LIB/$m.mod" ] && MODS="$MODS $m"
done

# Embedded config: find the partition holding our boot files, then load the
# real grub.cfg from it. Works for both USB (hd0) and CD (cd0) boot.
cat > "$WORK/grub-standalone.cfg" <<'STANDALONE'
search --file --no-floppy --set=root /boot/grub/grub.cfg
set prefix=($root)'/boot/grub'
configfile $prefix/grub.cfg
STANDALONE

grub-mkimage -O i386-pc -o "$WORK/core.img" \
  --config="$WORK/grub-standalone.cfg" -p '(cd0)/boot/grub' \
  $MODS
cat "$GRUB_LIB/boot.img" "$WORK/core.img" > "$WORK/eltorito.img"

mkdir -p "$WORK/isostage"
cp -a "$STAGE"/. "$WORK/isostage/" 2>/dev/null || true
mkdir -p "$WORK/isostage/boot/grub"
cp "$WORK/eltorito.img" "$WORK/isostage/boot/isolinux.bin" 2>/dev/null || true
cp "$WORK/eltorito.img" "$WORK/isostage/boot/grub/eltorito.img"
: > "$WORK/isostage/boot/boot.cat"

# ---------------------------------------------------------------- xorriso
ISOHYBRID_MBR=""
for p in /usr/lib/ISOLINUX/isohdpfx.bin /usr/share/syslinux/isohdpfx.bin; do
  [ -f "$p" ] && ISOHYBRID_MBR="$p" && break
done

XORRISO_ARGS=(
  -as mkisofs
  -V "YOGABOOK"
  -o "$OUT"
  -r -J
  -b boot/grub/eltorito.img -c boot/boot.cat
  -no-emul-boot -boot-load-size 4 -boot-info-table
)
[ -n "$ISOHYBRID_MBR" ] && XORRISO_ARGS+=( -isohybrid-mbr "$ISOHYBRID_MBR" )
XORRISO_ARGS+=(
  -eltorito-alt-boot
  -e --interval:appended_partition_2:all::
  -no-emul-boot
  -append_partition 2 0xef "$WORK/fat.img"
  -appended_part_as_gpt
  "$WORK/isostage"
)

xorriso "${XORRISO_ARGS[@]}"

echo
echo "ISO written: $OUT"
xorriso -indev "$OUT" -report_el_torito plain 2>/dev/null | head -20 || true
