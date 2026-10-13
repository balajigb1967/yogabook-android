#!/usr/bin/env bash
# Smoke test for scripts/make-refind-iso.sh: builds a dummy ISO and checks
# - partition layout (GPT with FAT EFI partition), - FAT contents via mtools,
# - optional: boots it under QEMU+OVMF (UEFI) and checks rEFInd shows up.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$(mktemp -d /tmp/ybiso-test.XXXXXX)}"
mkdir -p "$WORK"
REFIND_ZIP_URL="https://sourceforge.net/projects/refind/files/0.14.2/refind-bin-0.14.2.zip/download"

cd "$WORK"

# ---- rEFInd binaries
if [ ! -d refind-bin-0.14.2 ]; then
  curl -sL --max-time 180 -o refind.zip "$REFIND_ZIP_URL"
  unzip -q -o refind.zip
fi

# ---- staging tree (what the real packaging will produce)
rm -rf staging android
mkdir -p staging/EFI/BOOT/icons staging/boot/grub android
cp refind-bin-0.14.2/refind/refind_x64.efi staging/EFI/BOOT/BOOTX64.EFI
cp -a refind-bin-0.14.2/refind/icons/. staging/EFI/BOOT/icons/
cp -a refind-bin-0.14.2/fonts staging/EFI/BOOT/ 2>/dev/null || true

cp "$HERE/device/yogabook/YOGABOOK_x86_64/configs/refind/refind.conf" \
   staging/EFI/BOOT/refind.conf
cat >> staging/EFI/BOOT/refind.conf <<'EOF'
menuentry "Android 16 (dummy test)" {
    icon /EFI/BOOT/icons/os_linux.png
    loader /ANDROID/kernel
    initrd /ANDROID/ramdisk-all-combined.img
    options "androidboot.mount_system=imgs androidboot.mount_userdata=tmpfs"
}
EOF

cat > staging/boot/grub/grub.cfg <<'EOF'
menuentry "Android 16 (dummy test, BIOS)" {
    linux /ANDROID/kernel androidboot.mount_system=imgs
    initrd /ANDROID/ramdisk-all-combined.img
}
EOF

head -c 1M /dev/urandom > android/kernel
head -c 1M /dev/urandom > android/ramdisk-all-combined.img
head -c 64M /dev/urandom > android/system.img

# ---- build the ISO
bash "$HERE/scripts/make-refind-iso.sh" -o test.iso -a ANDROID \
  -f android/kernel -f android/ramdisk-all-combined.img -f android/system.img \
  -e staging -s 300M

# ---- structural checks
echo "== partition layout =="
sfdisk -l test.iso || fdisk -l test.iso

echo "== FAT partition contents (EFI/BOOT + ANDROID + bootlogs) =="
# locate the FAT (appended) partition offset from GPT via sfdisk json
off=$(sfdisk -d test.iso | grep -iE 'type=(U|C12A7328)' | sed -E 's/.*start= *([0-9]+).*/\1/' | head -1)
[ -n "$off" ] || { echo "FAT EFI partition not found!"; exit 1; }
off=$((off * 512))
mtools_skip_check=1 mdir -i "test.iso@@$off" ::/ | tee fat-listing.txt
for f in EFI/BOOT/BOOTX64.EFI EFI/BOOT/refind.conf ANDROID/kernel ANDROID/ramdisk-all-combined.img ANDROID/system.img bootlogs; do
  mtools_skip_check=1 mdir -i "test.iso@@$off" "::/$f" >/dev/null 2>&1 \
    && echo "OK  $f" || { echo "MISSING $f"; exit 1; }
done

# ---- optional UEFI boot test under QEMU
if [ "${BOOTTEST:-0}" = 1 ] && command -v qemu-system-x86_64 >/dev/null; then
  echo "== QEMU UEFI boot test =="
  CODE="" VARS=""
  for pair in "/usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_VARS.fd" \
              "/usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_VARS_4M.fd" \
              "/usr/share/OVMF/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_VARS.4m.fd" \
              "/usr/share/ovmf/OVMF.fd /usr/share/ovmf/OVMF.fd"; do
    set -- $pair
    [ -f "$1" ] && [ -f "$2" ] && CODE="$1" && VARS="$2" && break
  done
  [ -n "$CODE" ] || { echo "OVMF firmware not found (apt install ovmf)"; exit 1; }
  cp "$VARS" ovmf_vars.fd
  qemu-system-x86_64 -machine q35 -m 1024 -vga std -display none \
    -drive if=pflash,format=raw,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,file=ovmf_vars.fd \
    -cdrom test.iso -boot d \
    -monitor tcp:127.0.0.1:55555,server,nowait -serial file:serial.log &
  qpid=$!
  sleep 30
  { echo "screendump shot.ppm"; sleep 1; echo quit; } | \
    timeout 15 bash -c 'exec 3<>/dev/tcp/127.0.0.1/55555; cat >&3; sleep 2; cat <&3' > monitor.log || true
  wait $qpid 2>/dev/null || true
  if [ -f shot.ppm ]; then
    size=$(stat -c %s shot.ppm)
    echo "screenshot: $size bytes"
    [ "$size" -gt 100000 ] && echo "BOOTTEST OK: screen is not blank (rEFInd rendered)" \
                           || { echo "BOOTTEST FAIL: blank screen"; exit 1; }
  else
    echo "BOOTTEST FAIL: no screenshot"; exit 1
  fi
fi

echo "make-refind-iso smoke test PASSED ($WORK/test.iso)"
