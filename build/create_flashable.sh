#!/bin/bash
# Script to create flashable Android image for Yoga Book YB1-91F

echo "Creating flashable Android image for Yoga Book YB1-91F..."

# Check if build completed successfully
if [ ! -f "out/target/product/yogabook/system.img" ]; then
    echo "Error: Build output not found. Please run the build first."
    echo "Run: source build/envsetup.sh && lunch aosp_yogabook-userdebug && m"
    exit 1
fi

OUTPUT_DIR="out/target/product/yogabook"
FLASHABLE_DIR="flashable_yogabook_$(date +%Y%m%d_%H%M%S)"

# Create flashable directory
mkdir -p "$FLASHABLE_DIR"

# Copy essential images
echo "Copying Android system images..."
cp "$OUTPUT_DIR/system.img" "$FLASHABLE_DIR/"
cp "$OUTPUT_DIR/vendor.img" "$FLASHABLE_DIR/" 2>/dev/null || echo "Vendor image not found (A/B layout)"
cp "$OUTPUT_DIR/boot.img" "$FLASHABLE_DIR/"
cp "$OUTPUT_DIR/recovery.img" "$FLASHABLE_DIR/"
cp "$OUTPUT_DIR/vbmeta.img" "$FLASHABLE_DIR/"
cp "$OUTPUT_DIR/vbmeta_system.img" "$FLASHABLE_DIR/"

# Create flash script
cat > "$FLASHABLE_DIR/flash_yogabook.sh" << 'EOF'
#!/bin/bash
# Flash script for Yoga Book YB1-91F Android

echo "Flashing Android to Yoga Book YB1-91F..."
echo "Make sure device is in fastboot mode!"

# Check for fastboot
if ! command -v fastboot &> /dev/null; then
    echo "Error: fastboot not found. Please install Android Platform Tools."
    exit 1
fi

# Wait for device
echo "Waiting for device in fastboot mode..."
fastboot wait-for-device

# Flash images
echo "Flashing boot image..."
fastboot flash boot boot.img

echo "Flashing system image..."
fastboot flash system system.img

# Flash vendor if exists (A/B devices may not have separate vendor)
if [ -f vendor.img ]; then
    echo "Flashing vendor image..."
    fastboot flash vendor vendor.img
fi

echo "Flashing recovery image..."
fastboot flash recovery recovery.img

echo "Flashing vbmeta..."
fastboot flash vbmeta vbmeta.img

if [ -f vbmeta_system.img ]; then
    echo "Flashing vbmeta_system..."
    fastboot flash vbmeta_system vbmeta_system.img
fi

# Reboot
echo "Flashing complete! Rebooting device..."
fastboot reboot

echo "Device should now boot into Android"
EOF

chmod +x "$FLASHABLE_DIR/flash_yogabook.sh"

# Create README for flashable
cat > "$FLASHABLE_DIR/README.md" << EOF
# Yoga Book YB1-91F Android Flashable Image

This contains the Android build for Yoga Book YB1-91F.

## Contents
- boot.img - Boot image with kernel and ramdisk
- system.img - Android system partition
- vendor.img - Vendor partition (if applicable)
- recovery.img - Recovery image
- vbmeta.img - Verified boot metadata
- vbmeta_system.img - System verified boot metadata
- flash_yogabook.sh - Automated flash script

## Prerequisites
- Android Platform Tools (adb and fastboot)
- Yoga Book YB1-91F in fastboot mode

## Flashing Instructions
1. Connect Yoga Book via USB
2. Reboot to fastboot mode: `adb reboot bootloader` 
   OR hold Volume Down + Power on boot
3. Run: `./flash_yogabook.sh`
4. Device will automatically reboot into Android

## Working Features (based on base image)
- Touchscreen
- WiFi
- Bluetooth
- Auto-rotation

## Features in Progress
- HaloKeyboard (driver integration)
- Audio (RT5677 codec)
- LTE modem
- Camera (MBM sensors)

## Build Date
$(date)
EOF

echo "Flashable image created in: $FLASHABLE_DIR"
echo "To flash:"
echo "cd $FLASHABLE_DIR"
echo "./flash_yogabook.sh"