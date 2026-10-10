# Yoga Book YB1-91F Device Configuration

This directory contains the device-specific configuration for building Android on the Yoga Book YB1-91F.

## Files

- `AndroidProducts.mk` - Defines the product makefiles
- `yogabook.mk` - Main product definition
- `device-yogabook.mk` - Device-specific configurations and settings
- `manifest.xml` - HAL manifest for HIDL interfaces
- `compatibility_matrix.xml` - Compatibility matrix for VINTF
- `system.prop` - System properties
- `vendor.prop` - Vendor properties
- `product.prop` - Product properties
- `yogabook_defconfig` - Kernel configuration for 6.18 kernel

## Features Configured

### Working (from base image):
- Touchscreen (MBM touchscreen driver)
- WiFi 
- Bluetooth
- Auto-rotation/screen orientation

### To be implemented:
- HaloKeyboard (custom keyboard driver)
- Audio (RT5677 codec with ALSA UCM)
- LTE modem (Qualcomm MDM9x07)
- Camera (MBM sensors)

## Kernel Configuration

The `yogabook_defconfig` file contains the kernel configuration optimized for:
- ARM64 architecture (Cherry Trail platform)
- Yoga Book specific input devices
- Sound subsystem (RT5677 codec)
- Sensor hub (ThinkPad ACPI)
- Power management for 2-in-1 convertible

## Building

To build Android for Yoga Book YB1-91F:

1. Initialize repo: `repo init -u https://android.googlesource.com/platform/manifest -b android-13.0.0_r41`
2. Copy local manifest: `cp build/yogabook.xml .repo/local_manifests/`
3. Sync sources: `repo sync -j$(nproc)`
4. Apply kernel patches: `build/apply_kernel_patches.sh`
5. Setup environment: `source build/envsetup.sh`
6. Select target: `lunch aosp_yogabook-userdebug`
7. Build: `m -j$(nproc)`

## Dependencies

This configuration relies on the following Yoga Book repositories:
- Kernel: https://github.com/Yoga-Book/Yoga-Book-Linux-Kernel (submission/yogabook-x91l-v2)
- Sound Firmware: https://github.com/Yoga-Book/Yoga-Book-Sound-Open-Firmware (submission/cht-rt5677-topology2-ipc3-v1)
- Camera: https://github.com/Yoga-Book/Yoga-Book-Camera
- Halo Keyboard: https://github.com/Yoga-Book/Halo-Keyboard
- Sensors: https://github.com/Yoga-Book/Yoga-Book-Sensors
- ALSA UCM Config: https://github.com/Yoga-Book/Yoga-Book-ALSA-UCM-Config
- Mutter (for native portrait): https://github.com/Yoga-Book/mutter (submission/work-item-4204-native-portrait-v2)