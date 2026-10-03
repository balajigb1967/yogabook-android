# Lenovo Yoga Book (YB1-X91F) Driver & Hardware Module Bundle

This bundle contains backported drivers, firmware, udev rules, audio profiles, and daemons from the official Yoga-Book organization:
- **Halo Keyboard:** https://github.com/Yoga-Book/Halo-Keyboard
- **Sound Open Firmware (SOF):** https://github.com/Yoga-Book/Yoga-Book-Sound-Open-Firmware
- **ALSA UCM Audio Profiles:** https://github.com/Yoga-Book/Yoga-Book-ALSA-UCM-Config
- **Camera Configurations:** https://github.com/Yoga-Book/Yoga-Book-Camera
- **Sensors:** https://github.com/Yoga-Book/Yoga-Book-Sensors

---

## 1. Sound / Audio Setup
1. Copy `audio/sof-firmware/sof-cht-rt5677.tplg` to:
   `/vendor/firmware/intel/sof-tplg/sof-cht-rt5677.tplg` (or `/system/etc/firmware/`)
2. Copy the UCM profiles in `audio/alsa-ucm/ucm2/` to:
   `/vendor/etc/alsa/ucm2/` or `/usr/share/alsa/ucm2/`

---

## 2. Halo Keyboard Daemon & Layouts
The Yoga Book's Halo Keyboard surface operates as a Goodix touch sensor.
1. Key mapping configs are located in `halo-keyboard/config/`.
2. Udev rules are in `halo-keyboard/udev/`.

---

## 3. Sensors & Accelerometer (Auto-Rotation)
1. Udev rules are located in `sensors/udev/`.
2. Scripts are located in `sensors/libexec/`.

---

## 4. Camera Setup
1. Modprobe configs are in `camera/modprobe.d/`.
2. Load rules are in `camera/modules-load.d/`.
3. Udev rules are in `camera/udev/`.

---

## How to Apply via KernelSU / Magisk on Bliss OS 16
Because Android 13's system partition is read-only EROFS, you can install the **KernelSU app**, create a module in `/data/adb/modules/yogabook/`, and place firmware and configuration files under `/data/adb/modules/yogabook/system/` so they are overlaid transparently without modifying the read-only ROM.
