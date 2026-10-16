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

menuentry "Yoga Book Android-x86 - Auto-Install (Kernel 6.18-zenith - Recommended)" {
    set gfxpayload=keep
    search --no-floppy --file --set=root /ANDRID/kernel-6.18
    echo "Loading Yoga Book Kernel 6.18 Unattended Installer..."
    linux /ANDRID/kernel-6.18 androidboot.hardware=android_x86 video=DSI-1:1200x1920,rotate=90 fbcon=rotate:1 DPI=240 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID sdhci.debug_quirks2=0x04 INSTALL=1 AUTO_INSTALL=auto
    echo "Loading Initrd..."
    initrd /ANDRID/initrd.img
}

menuentry "Yoga Book Android-x86 - Live Mode (Kernel 6.18-zenith)" {
    set gfxpayload=keep
    search --no-floppy --file --set=root /ANDRID/kernel-6.18
    echo "Loading Yoga Book Kernel 6.18 Live Mode..."
    linux /ANDRID/kernel-6.18 androidboot.hardware=android_x86 video=DSI-1:1200x1920,rotate=90 fbcon=rotate:1 DPI=240 HWC=drm GRALLOC=gbm ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID sdhci.debug_quirks2=0x04 quiet
    echo "Loading Initrd..."
    initrd /ANDRID/initrd.img
}

menuentry "Yoga Book Android-x86 - Verbose Debug Mode (Kernel 6.18 - Detailed Logs)" {
    set gfxpayload=keep
    search --no-floppy --file --set=root /ANDRID/kernel-6.18
    echo "Loading Yoga Book Kernel 6.18 in Verbose Debug Mode..."
    linux /ANDRID/kernel-6.18 androidboot.hardware=android_x86 video=DSI-1:1200x1920,rotate=90 fbcon=rotate:1 DPI=240 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID sdhci.debug_quirks2=0x04 console=tty0 DEBUG=2
    echo "Loading Initrd..."
    initrd /ANDRID/initrd.img
}

menuentry "Yoga Book Android-x86 - Auto-Install (Kernel 7.2 Mainline)" {
    set gfxpayload=keep
    search --no-floppy --file --set=root /ANDRID/kernel-7.2
    echo "Loading Yoga Book Kernel 7.2 Unattended Installer..."
    linux /ANDRID/kernel-7.2 androidboot.hardware=android_x86 video=DSI-1:1200x1920,rotate=90 fbcon=rotate:1 DPI=240 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive SRC=/ANDRID sdhci.debug_quirks2=0x04 INSTALL=1 AUTO_INSTALL=auto
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
