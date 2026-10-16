#!/usr/bin/env python3
"""
update_grub_cfg.py - Updates grub.cfg on D: to include explicit search commands
so GRUB always locates /ANDRID/kernel before trying to load it.
"""

CFG = """set timeout=5
set default=0

search --no-floppy --file --set=root /ANDRID/kernel

loadfont unicode || true
set gfxmode=auto
set gfxpayload=keep
terminal_output gfxterm console || true

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "Yoga Book Android-x86 - Auto-Install to eMMC [Wipes BlissOS - Default]" {
    set gfxpayload=keep
    search --no-floppy --file --set=root /ANDRID/kernel
    echo "Loading Android-x86 Unattended Installer..."
    linux /ANDRID/kernel androidboot.hardware=android_x86_64 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID ROOT="/dev/mmcblk0p1 /dev/mmcblk1p1 /dev/sda1" sdhci.debug_quirks2=0x04 INSTALL=1 AUTO_INSTALL=auto
    echo "Loading Initrd..."
    initrd /ANDRID/initrd.img
}

menuentry "Yoga Book Android-x86 - Standard Live Mode" {
    set gfxpayload=keep
    search --no-floppy --file --set=root /ANDRID/kernel
    echo "Loading Yoga Book Kernel in Live Mode from SD Card..."
    linux /ANDRID/kernel androidboot.hardware=android_x86_64 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID ROOT="/dev/mmcblk0p1 /dev/mmcblk1p1 /dev/sda1" sdhci.debug_quirks2=0x04 quiet
    echo "Loading Initrd..."
    initrd /ANDRID/initrd.img
}

menuentry "Yoga Book Android-x86 - Verbose Console" {
    set gfxpayload=keep
    search --no-floppy --file --set=root /ANDRID/kernel
    echo "Loading Yoga Book Kernel in Verbose Mode..."
    linux /ANDRID/kernel androidboot.hardware=android_x86_64 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID ROOT="/dev/mmcblk0p1 /dev/mmcblk1p1 /dev/sda1" sdhci.debug_quirks2=0x04 console=tty0 DEBUG=2
    echo "Loading Initrd..."
    initrd /ANDRID/initrd.img
}

menuentry "Reboot System" {
    reboot
}

menuentry "Power Off" {
    halt
}
"""

if __name__ == '__main__':
    for path in ['D:/boot/grub/grub.cfg', 'D:/EFI/BOOT/grub.cfg']:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(CFG)
        print(f"Updated {path}")
