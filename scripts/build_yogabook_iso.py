#!/usr/bin/env python3
"""
build_yogabook_iso.py
Builds a bootable hybrid UEFI/BIOS ISO for the Lenovo Yoga Book (YB1-X91L / YB1-X90F)
incorporating the Bass OS Calamares Graphical Touch/Mouse Installer.
"""

import os
import sys
import subprocess
import shutil

BASE_DIR = r"c:\Yogabook"
ISO_BUILD_DIR = os.path.join(BASE_DIR, "iso_build")
TOOLS_DIR = os.path.join(BASE_DIR, "tools")
XORRISO_EXE = os.path.join(TOOLS_DIR, "xorriso.exe")
DIST_DIR = os.path.join(BASE_DIR, "dist")
OUTPUT_ISO_NAME = "YogaBook-LineageOS-23.2-Calamares-x86_64.iso"
OUTPUT_ISO_PATH = os.path.join(DIST_DIR, OUTPUT_ISO_NAME)
DOWNLOADS_DIR = r"C:\Users\Admin\Downloads"
DOWNLOADS_ISO_PATH = os.path.join(DOWNLOADS_DIR, OUTPUT_ISO_NAME)

ORIGINAL_ISO = r"C:\Users\Admin\Downloads\bass-lineout-23.2-2026092600-Desktop-Zenith-x86_64_tablet.iso"

# 1. Update cmdline.txt
cmdline_file = os.path.join(ISO_BUILD_DIR, "cmdline.txt")
cmdline_content = (
    "video=DSI-1:1200x1920,rotate=90 fbcon=rotate:1 DPI=240 "
    "ro.surface_flinger.primary_display_orientation=ORIENTATION_90 "
    "sdhci.debug_quirks2=0x04 androidboot.selinux=permissive\n"
)
print(f"Writing {cmdline_file}...")
with open(cmdline_file, "w", encoding="utf-8") as f:
    f.write(cmdline_content)

# 2. Update boot/grub/grub.cfg
grub_cfg_file = os.path.join(ISO_BUILD_DIR, "boot", "grub", "grub.cfg")
# Remove read-only attribute if set
try:
    os.chmod(grub_cfg_file, 0o666)
except Exception:
    pass

grub_cfg_content = """insmod part_gpt
insmod part_msdos
insmod part_apple
insmod all_video
insmod regexp

set default="0"
set timeout=15
set gfxpayload=keep

set TITLE="Yoga Book LineageOS 23.2 (Kernel 7.2)"
set YB_COMMON="video=DSI-1:1200x1920,rotate=90 fbcon=rotate:1 DPI=240 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 sdhci.debug_quirks2=0x04 androidboot.selinux=permissive"
set KERNEL_ARGS="root=/dev/ram0 androidboot.live=true ROOT=LABEL=YOGABOOK_OS $YB_COMMON"
set KERNEL=/kernel
set INITRD=/initrd.img

if [ "$RELOAD" != "true" ]; then
\tsource /boot/grub/functions.cfg
\tsource /boot/grub/features.cfg
fi

if is_efi; then
\tinsmod efi_gop
\tinsmod efi_uga
fi

if [ "$root" == "loop0" ]; then
\tset prefix=($root)/boot/grub
fi

insmod jpeg
insmod png
load_theme

if [ -z "$src" -a -n "$isofile" ]; then
\tset iso="iso-scan/filename=$isofile"
fi

# Entry 0: Calamares Graphical Touch/Mouse Installer (Default)
menuentry "Yoga Book LineageOS 23.2 (Kernel 7.2) - Graphical Touch/Mouse Installer (Calamares - Default)" --class blissos {
\tlinux "($root)${KERNEL}" $KERNEL_ARGS "INSTALL=install.sfs" "$pcmode" "$ffmpeg" "$hwaccel" "$setupwizard" "$copytoram" "$iso"
\tinitrd "($root)${INITRD}"
}

# Entry 1: Live Desktop (Hardware Accelerated)
menuentry "Yoga Book LineageOS 23.2 (Kernel 7.2) - Live Mode (Hardware Accelerated)" --class blissos {
\tlinux "($root)${KERNEL}" $KERNEL_ARGS "$pcmode" "$ffmpeg" "$hwaccel" "$setupwizard" "$copytoram" "$iso"
\tinitrd "($root)${INITRD}"
}

# Entry 2: Live Desktop (Software Rendering Fallback)
menuentry "Yoga Book LineageOS 23.2 (Kernel 7.2) - Live Mode (Software Rendering Fallback - HWACCEL=0 nomodeset)" --class blissos {
\tlinux "($root)${KERNEL}" $KERNEL_ARGS "nomodeset HWACCEL=0" "$pcmode" "$ffmpeg" "$setupwizard" "$copytoram" "$iso"
\tinitrd "($root)${INITRD}"
}

submenu --class brunch-settings --class forward "Advanced options" {
\ttoggle_ffmpeg
\ttoggle_pcmode
\ttoggle_hwaccel
\ttoggle_setupwizard
\ttoggle_copytoram
}

efi_detect
memtest_detect
power_options
"""

print(f"Writing {grub_cfg_file}...")
with open(grub_cfg_file, "w", encoding="utf-8") as f:
    f.write(grub_cfg_content)

# 3. Prepare output directory
os.makedirs(DIST_DIR, exist_ok=True)
if os.path.exists(OUTPUT_ISO_PATH):
    print(f"Removing old {OUTPUT_ISO_PATH}...")
    os.remove(OUTPUT_ISO_PATH)

# Convert Windows paths to Cygwin paths for xorriso
def to_cygwin(path):
    path = os.path.abspath(path).replace("\\", "/")
    if len(path) >= 2 and path[1] == ":":
        drive = path[0].lower()
        return f"/cygdrive/{drive}{path[2:]}"
    return path

cyg_orig_iso = to_cygwin(ORIGINAL_ISO)
cyg_iso_build = to_cygwin(ISO_BUILD_DIR)
cyg_output_iso = to_cygwin(OUTPUT_ISO_PATH)

xorriso_cmd = [
    XORRISO_EXE,
    "-as", "mkisofs",
    "-V", "YOGABOOK_OS",
    "--modification-date=2026101708000000",
    "--grub2-mbr", f"--interval:local_fs:0s-15s:zero_mbrpt,zero_gpt,zero_apm:{cyg_orig_iso}",
    "--protective-msdos-label",
    "-partition_cyl_align", "off",
    "-partition_offset", "0",
    "-partition_hd_cyl", "208",
    "-partition_sec_hd", "32",
    "-apm-block-size", "2048",
    "-hfsplus",
    "-efi-boot-part", "--efi-boot-image",
    "-c", "/boot.catalog",
    "-b", "/boot/grub/i386-pc/eltorito.img",
    "-no-emul-boot",
    "-boot-load-size", "4",
    "-boot-info-table",
    "--grub2-boot-info",
    "-eltorito-alt-boot",
    "-e", "/efi.img",
    "-no-emul-boot",
    "-boot-load-size", "5760",
    "-o", cyg_output_iso,
    cyg_iso_build,
]

print("Executing xorriso...")
print("Command:", " ".join(xorriso_cmd))
result = subprocess.run(xorriso_cmd)
if result.returncode != 0:
    print(f"ERROR: xorriso failed with exit code {result.returncode}")
    sys.exit(result.returncode)

if not os.path.exists(OUTPUT_ISO_PATH):
    print("ERROR: Output ISO was not created!")
    sys.exit(1)

iso_size = os.path.getsize(OUTPUT_ISO_PATH)
print(f"SUCCESS: Built {OUTPUT_ISO_PATH} ({iso_size:,} bytes, {iso_size / (1024**3):.2f} GB)")

# 4. Copy to Desktop & Downloads for user
desktop_dir = os.path.join(os.environ.get("USERPROFILE", r"C:\Users\Admin"), "Desktop")
desktop_iso_path = os.path.join(desktop_dir, OUTPUT_ISO_NAME)
print(f"Copying to {desktop_iso_path}...")
shutil.copy2(OUTPUT_ISO_PATH, desktop_iso_path)
print(f"Copying to {DOWNLOADS_ISO_PATH}...")
shutil.copy2(OUTPUT_ISO_PATH, DOWNLOADS_ISO_PATH)
print("Copied successfully to Desktop and Downloads.")
