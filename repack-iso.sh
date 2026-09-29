#!/usr/bin/env bash
# repack-iso.sh — Inject the Yoga Book kernel + modules + firmware into a
# Bliss/Bass 16.9.7 (Android-x86) ISO and rebuild it, keeping the original
# boot records (BIOS isohybrid MBR + El Torito + UEFI) intact via xorriso.
#
# Usage: repack-iso.sh <base.iso> <bzImage> <modules.tar.gz> <out.iso> [fw-dir]
#
# What happens:
#   1. initrd.img (and ramdisk.img if present) are unpacked
#   2. /kernel is replaced with the Yoga Book bzImage
#   3. our /lib/modules/<krel> + /vendor/firmware additions are merged in
#   4. initrd/ramdisk are repacked (Android-x86 supports both gzip and lz4)
#   5. ISO is rebuilt with xorriso: isohybrid MBR + UEFI El Torito preserved
set -euo pipefail

BASE="${1:?usage: repack-iso.sh <base.iso> <bzImage> <modules.tar.gz> <out.iso> [fw-dir]}"
BZIMAGE="${2:?missing bzImage}"
MODULES_TGZ="${3:?missing modules.tar.gz}"
OUT="${4:?missing out.iso}"
FW_DIR="${5:-}"

WORK="$(mktemp -d /tmp/repack-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/iso" "$WORK/initrd" "$WORK/ramdisk"

command -v xorriso >/dev/null || { echo "ERROR: xorriso is required" >&2; exit 1; }

echo ">>> Extracting base ISO"
xorriso -osirrox on -indev "$BASE" -extract / "$WORK/iso" >/dev/null 2>&1

echo ">>> Base ISO contents:"
ls -lh "$WORK/iso"

[[ -f "$WORK/iso/kernel" ]] || { echo "ERROR: no /kernel in ISO — not an Android-x86 layout?" >&2; exit 1; }

echo ">>> Replacing kernel"
install -m 0644 "$BZIMAGE" "$WORK/iso/kernel"

# ---- initrd.img: unpack, add modules + firmware, repack ----
unpack_cpio() {
    local img="$1" dir="$2"
    mkdir -p "$dir"
    ( cd "$dir" && ( xzcat "$img" 2>/dev/null || zcat "$img" 2>/dev/null \
        || lz4 -d "$img" 2>/dev/null || cat "$img" ) | cpio -idm --quiet )
}

repack_cpio() {
    local dir="$1" out="$2"
    ( cd "$dir" && find . -print0 | cpio --null -o -H newc --quiet | gzip -9 ) > "$out"
}

echo ">>> Unpacking initrd.img"
unpack_cpio "$WORK/iso/initrd.img" "$WORK/initrd"

echo ">>> Merging module tree into initrd"
tar xzf "$MODULES_TGZ" -C "$WORK/initrd"

if [[ -n "$FW_DIR" && -d "$FW_DIR" ]]; then
    echo ">>> Merging extra firmware into initrd/vendor/firmware"
    mkdir -p "$WORK/initrd/vendor/firmware"
    cp -rv "$FW_DIR"/. "$WORK/initrd/vendor/firmware/" || true
fi

# Drop stale module dirs from the base ISO so the new kernel's modules win
for d in "$WORK"/initrd/lib/modules/*; do
    KREL="$(cat "$(dirname "$0")/artifacts/KREL" 2>/dev/null || basename "$MODULES_TGZ" | sed 's/^modules-//; s/\.tar\.gz$//')"
    [[ "$(basename "$d")" == "$KREL" ]] || { echo "    removing stale modules: $(basename "$d")"; rm -rf "$d"; }
done

echo ">>> Repacking initrd.img (lz4, as Android-x86 boot scripts expect)"
( cd "$WORK/initrd" && find . -print0 | cpio --null -o -H newc --quiet | lz4 -9 -l ) \
    > "$WORK/iso/initrd.img" 2>/dev/null || \
repack_cpio "$WORK/initrd" "$WORK/iso/initrd.img"

# ---- ramdisk.img: add the same module tree so installed boot also has them ----
if [[ -f "$WORK/iso/ramdisk.img" ]]; then
    echo ">>> Unpacking ramdisk.img"
    unpack_cpio "$WORK/iso/ramdisk.img" "$WORK/ramdisk"
    tar xzf "$MODULES_TGZ" -C "$WORK/ramdisk"
    echo ">>> Repacking ramdisk.img (gzip)"
    repack_cpio "$WORK/ramdisk" "$WORK/iso/ramdisk.img"
fi

# ---- rebuild the ISO preserving the original El Torito boot records ----
# xorriso's as_mkisofs report gives the EXACT options the base ISO was built
# with (-V, -b isolinux.bin, -e efiboot.img, ...), so we reuse them verbatim
# instead of guessing paths.
OPTS="$(xorriso -indev "$BASE" -report_el_torito as_mkisofs 2>/dev/null | tr '\n' ' ' | xargs || true)"

echo ">>> Rebuilding $OUT (boot opts: ${OPTS:-<fallback BIOS-only>})"
rm -f "$OUT"

# GPT hybrid is only valid when an EFI El Torito record exists
GPT=""
case " $OPTS " in
    *" -e "*) GPT="-isohybrid-gpt-basdat" ;;
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
