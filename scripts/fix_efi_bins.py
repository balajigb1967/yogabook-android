#!/usr/bin/env python3
"""
fix_efi_bins.py - Patches standalone BOOTX64.EFI and BOOTIA32.EFI binaries
to replace the broken 814-byte embedded script with valid GRUB syntax.
"""

import os
import sys

TARGET_LEN = 814

NEW_SCRIPT = """set echo=0
set timeout=3
set default=0

search --no-floppy --file --set=cfg_root /EFI/BOOT/grub.cfg
if [ -n "$cfg_root" ]; then
    set prefix=($cfg_root)/EFI/BOOT
    configfile ($cfg_root)/EFI/BOOT/grub.cfg
fi

search --no-floppy --file --set=cfg_root2 /boot/grub/grub.cfg
if [ -n "$cfg_root2" ]; then
    set prefix=($cfg_root2)/boot/grub
    configfile ($cfg_root2)/boot/grub/grub.cfg
fi

search --no-floppy --file --set=root /kernel
if [ -n "$root" ]; then
    menuentry "Yoga Book Android-x86" {
        set gfxpayload=keep
        linux /kernel androidboot.hardware=android_x86 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive sdhci.debug_quirks2=0x04 quiet
        initrd /initrd.img
    }
fi
"""

pad_len = TARGET_LEN - len(NEW_SCRIPT)
if pad_len < 0:
    raise ValueError(f"Script too long ({len(NEW_SCRIPT)} > {TARGET_LEN})")
PADDED_SCRIPT = NEW_SCRIPT + ("# " + "=" * (pad_len - 3) + "\n")
assert len(PADDED_SCRIPT) == TARGET_LEN, f"Expected {TARGET_LEN}, got {len(PADDED_SCRIPT)}"

def patch_efi(path: str):
    if not os.path.exists(path):
        print(f"Skipping {path} (not found)")
        return
    with open(path, "rb") as f:
        data = bytearray(f.read())
    
    idx = data.find(b"set echo=1")
    if idx == -1:
        print(f"Could not find 'set echo=1' in {path}")
        return
    
    end = data.find(b"}\nfi\n", idx)
    if end == -1:
        print(f"Could not find end marker '}}\\nfi\\n' in {path}")
        return
    end += 5
    old_len = end - idx
    if old_len != TARGET_LEN:
        print(f"Warning: old script length is {old_len}, expected {TARGET_LEN}")
    
    data[idx:idx + TARGET_LEN] = PADDED_SCRIPT.encode("latin1")
    with open(path, "wb") as f:
        f.write(data)
    print(f"Successfully patched {path} ({len(data)} bytes, replaced {TARGET_LEN} bytes)")

if __name__ == "__main__":
    for p in ["D:/EFI/BOOT/BOOTX64.EFI", "D:/EFI/BOOT/BOOTIA32.EFI"]:
        patch_efi(p)
