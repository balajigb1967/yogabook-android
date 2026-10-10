#!/bin/bash
# Script to apply Yoga Book specific patches to the 6.18 kernel

echo "Applying Yoga Book specific kernel patches..."

KERNEL_DIR="kernel/lenovo/yogabook"
PATCH_DIR="device/lenovo/yogabook/patches"

# Create patches directory if it doesn't exist
mkdir -p "$PATCH_DIR"

# Check if kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
    echo "Error: Kernel directory not found at $KERNEL_DIR"
    echo "Please run repo sync first to fetch the kernel source"
    exit 1
fi

cd "$KERNEL_DIR"

# Apply Yoga Book specific configurations
echo "Applying Yoga Book defconfig..."
if [ -f "../../device/lenovo/yogabook/yogabook_defconfig" ]; then
    cp "../../device/lenovo/yogabook/yogabook_defconfig" arch/arm64/configs/
fi

# Apply backports for specific drivers if needed
echo "Checking for driver backports needed..."

# HaloKeyboard driver backport (if needed for 6.18)
if [ ! -f "drivers/input/keyboard/halo_keyboard.c" ]; then
    echo "HaloKeyboard driver not found - may need backport"
fi

# Sound driver backports (RT5677)
if [ ! -f "sound/soc/codecs/rt5677*" ]; then
    echo "RT5677 sound codec driver not found - may need backport from 5.4+ kernel"
fi

# Camera driver backports
if [ ! -f "drivers/media/platform/mbm*" ]; then
    echo "MBM camera driver not found - may need backport"
fi

# Sensor hub backports
if [ ! -f "drivers/platform/x86/thinkpad_acpi*" ]; then
    echo "ThinkPad ACPI sensor driver not found - may need adaptation"
fi

echo "Kernel patch application complete"
echo "Next steps:"
echo "1. Review any missing drivers that need backporting"
echo "2. Configure kernel: make ARCH=arm64 yogabook_defconfig"
echo "3. Build kernel: make -j\$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"