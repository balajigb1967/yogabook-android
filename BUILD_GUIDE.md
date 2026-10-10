# Yoga Book YB1-91F Android Build Guide

This guide explains how to build Android for the Yoga Book YB1-91F tablet using the provided base image and Yoga Book specific repositories.

## Overview

We're building Android 13 for the Yoga Book YB1-91F based on:
- Base image: https://drive.google.com/file/d/1_mSGxkezecd-P-WrravRuaXY923UEIll/view?usp=drive_link (6.18 kernel)
- Yoga Book specific drivers from various repositories
- Either backporting drivers to 6.18 kernel or attempting Android on 7.2+ kernel

## Prerequisites

### Host System Requirements
- Ubuntu 20.04 or later (recommended) or Windows with WSL2
- ~100GB free disk space
- 8GB+ RAM recommended
- Git, repo tool, Java JDK 11
- Android Platform Tools (adb, fastboot)

### Software Installation
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install git-core gnupg flex bison gperf build-essential \
  zip curl zlib1g-dev libc6-dev lib32ncurses6 lib32z1 lib32stdc++6 \
  libssl-dev libffi-dev lib32z1-dev lsb-release

# Install repo
mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH=~/bin:$PATH

# Install Java JDK 11
sudo apt-get install openjdk-11-jdk
```

## Step-by-Step Build Process

### 1. Initialize the Repository
```bash
cd yogabook-android
repo init -u https://android.googlesource.com/platform/manifest -b android-13.0.0_r41
```

### 2. Add Yoga Book Local Manifest
```bash
cp build/yogabook.xml .repo/local_manifests/
```

### 3. Sync All Sources
```bash
repo sync -j$(nproc)
```
This will download:
- AOSP Android 13 base
- Yoga Book Linux Kernel (6.18 base with Yoga Book patches)
- Yoga Book Sound Firmware (RT5677)
- Yoga Book Camera drivers
- Yoga Book Halo Keyboard drivers
- Yoga Book Sensors drivers
- Yoga Book ALSA UCM Configuration
- Yoga Book Mutter (for native portrait support)

### 4. Apply Kernel Patches and Configuration
```bash
build/apply_kernel_patches.sh
```

### 5. Configure Kernel (if needed)
```bash
cd kernel/lenovo/yogabook
make ARCH=arm64 yogabook_defconfig
# Review and modify config if necessary
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
```

### 6. Setup Android Build Environment
```bash
cd ../..
source build/envsetup.sh
yogabook_lunch  # Selects aosp_yogabook-userdebug by default
```

### 7. Build Android
```bash
m -j$(nproc)
```
Build time: 1-3 hours depending on hardware

### 8. Create Flashable Image
```bash
build/create_flashable.sh
```
Output: `flashable_yogabook_YYYYMMDD_HHMMSS/` directory

### 9. Flash to Device
```bash
# Enable developer options and USB debugging on device first
adb reboot bootloader
# Or boot with Volume Down + Power

cd flashable_yogabook_*/ 
./flash_yogabook.sh
```

## Working Features (from Base Image)

The base image already provides:
- ✅ Touchscreen (MBM touchscreen controller)
- ✅ WiFi (RTL8723BS)
- ✅ Bluetooth (RTL8723BS)  
- ✅ Auto-rotation/screen orientation
- ✅ Basic display output

## Features to Implement

These require driver integration from the Yoga Book repositories:

### 🔧 HaloKeyboard
- Repository: https://github.com/Yoga-Book/Halo-Keyboard
- Location: `vendor/lenovo/yogabook/halo-keyboard`
- Needed: Custom keyboard driver and HAL service
- Config: `CONFIG_INPUT_HALOKEYBOARD` in kernel

### 🔊 Audio (RT5677 Codec)
- Repository: https://github.com/Yoga-Book/Yoga-Book-Sound-Open-Firmware (submission/cht-rt5677-topology2-ipc3-v1)
- Repository: https://github.com/Yoga-Book/Yoga-Book-ALSA-UCM-Config
- Needed: RT5677 codec driver + ALSA UCM configuration
- Kernel: `CONFIG_SND_SOC_RT5677`
- HAL: `android.hardware.audio@6.0-service.yogabook`

### 📶 LTE Modem
- Likely: Qualcomm MDM9x07 based on Yoga Book LTE variants
- Needed: QMI/RMNET drivers and RIL implementation
- Currently: Not working in base image

### 📷 Camera (MBM Sensors)
- Repository: https://github.com/Yoga-Book/Yoga-Book-Camera
- Needed: MBM camera sensor drivers and camera HAL
- Kernel: `CONFIG_INPUT_MBM_TOUCSCREEN` (touchscreen shares sensor hub)
- HAL: `android.hardware.camera.provider@2.4-service.yogabook`

## Troubleshooting

### Build Failures
1. **Missing dependencies**: Ensure all build packages are installed
2. **Java version issues**: Use JDK 11 specifically
3. **Out of memory**: Increase swap space or reduce `-j` parallelism
4. **Kernel config issues**: Check `yogabook_defconfig` for missing options

### Boot Issues
1. **Bootloop**: Check kernel config and initramfs
2. **No display**: Verify display drivers and framebuffer config
3. **Touch not working**: Check input device drivers and IDC files
4. **WiFi/BT not working**: Verify firmware loading and regulator configs

### Specific Component Issues

#### HaloKeyboard Not Working
- Verify `CONFIG_INPUT_HALOKEYBOARD=y` in kernel config
- Check that `halokeyboard.rc` service starts properly
- Look for input events with `getevent | grep -i halo`

#### Audio Not Working
- Verify RT5677 codec is detected: `dmesg | grep -i rt5677`
- Check ALSA mixer controls: `tinymix`
- Test audio routing: `tinycap` and `tinyplay`

#### Camera Not Working
- Check if MBM sensors are detected: `dmesg | grep -i mbm`
- Verify camera HAL service is running: `ps | grep camera`
- Test with camera app after granting permissions

#### LTE Not Working
- Check for modem device: `ls /dev/ttyUSB* /dev/cdc-*`
- Verify RIL daemon is running: `ps | grep ril`
- Test with `mmcli` if ModemManager is available

## Kernel Backporting Approach

If drivers need to be backported to 6.18 kernel:

1. Identify missing drivers from Yoga Book repos
2. Compare with mainline Linux or LTS kernels where they exist
3. Backport using:
   ```bash
   git format-patch -p <base_commit>..<feature_branch>
   git apply <patch_series>
   ```
4. Resolve any conflicts or API changes
5. Test compilation and basic functionality

## Alternative: Android on 7.2+ Kernel

If preferring to move to newer kernel:
1. Update `TARGET_KERNEL_SOURCE` to point to newer LTS kernel
2. Port Yoga Book specific patches to newer kernel base
3. Update kernel config (`yogabook_defconfig`) for new kernel version
4. Test with Android Generic Kernel Image (GKI) approach if applicable

## Validation

After successful build and flash:
1. Verify Android boots to home screen
2. Test touchscreen responsiveness
3. Verify WiFi connects and works
4. Test Bluetooth pairing
5. Check auto-rotation with sensor tests
6. Implement and test each missing feature incrementally

## References

- Yoga Book Linux Kernel: https://github.com/Yoga-Book/Yoga-Book-Linux-Kernel
- Yoga Book Sound Firmware: https://github.com/Yoga-Book/Yoga-Book-Sound-Open-Firmware
- Yoga Book Camera: https://github.com/Yoga-Book/Yoga-Book-Camera
- Yoga Book Halo Keyboard: https://github.com/Yoga-Book/Halo-Keyboard
- Yoga Book Sensors: https://github.com/Yoga-Book/Yoga-Book-Sensors
- Yoga Book ALSA UCM Config: https://github.com/Yoga-Book/Yoga-Book-ALSA-UCM-Config
- Yoga Book Mutter: https://github.com/Yoga-Book/mutter
- Ubuntu Autoinstall (reference): https://github.com/Yoga-Book/Ubuntu-Autoinstall

## Notes

This build is configured for:
- Device: Yoga Book YB1-91F (yb1-91f model)
- Architecture: ARM64 (Cherry Trail/Atom x5-Z8350)
- Android Version: 13.0
- Kernel Base: 6.18 (from provided base image)
- Build Type: userdebug (for development) or eng (for engineering)

For production builds, change to `aosp_yogabook-user` or create a custom user variant.