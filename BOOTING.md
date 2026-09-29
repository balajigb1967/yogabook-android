# Flashing & First Boot — Yoga Book YB1-X91F

## ⚡ One-touch install (NO keyboard needed)
1. Flash the ISO to USB (step 2 below) and plug it into the Yoga Book.
2. Power on holding **Volume Up** → pick USB.
3. **Do nothing.** The default GRUB entry (3 s) starts the guarded
   auto-installer: it erases the internal eMMC (only after verifying the
   device really is a Yoga Book), copies Android over, installs GRUB, and
   **powers the tablet off by itself**.
4. Remove the USB stick, power on → Android boots from eMMC.

(To just try it live without installing, pick the second GRUB entry
"Live boot (no install)" — but that needs arrow keys/USB keyboard.)

---

## 0. Prerequisites
- A USB stick, **4 GB+** (everything on it is erased)
- `YogaBook-BassOS-16.9.7-<date>-x86_64.iso` from Actions artifacts / Releases
- Rufus (Windows) or balenaEtcher (any OS)
- Strongly recommended for setup: a USB keyboard via a **powered** OTG/micro-USB hub
- Yoga Book charged to 50%+

## 1. Disable Secure Boot (once)
1. Power off. Hold **Volume Up + Power** until the boot menu appears.
2. Choose **BIOS Setup**, find *Security → Secure Boot*, set **Disabled**.
3. Save & exit (F10), power off.

## 2. Flash the USB stick
- **Rufus:** select the ISO, partition scheme *GPT/UEFI*, write mode **DD image mode** (Rufus asks — choose DD, not ISO mode).
- **Etcher:** select ISO → USB → Flash.
- Verify SHA256 against the build output if you like.

## 3. Boot from USB
1. Connect the OTG hub → USB stick (+ USB keyboard).
2. Power on holding **Volume Up** → pick the USB drive in the boot menu.
3. The **GRUB menu** appears. Start with the plain `Boot Bliss OS` entry (live, no install).

## 4. First boot — what to expect
| Component | Status |
|---|---|
| Screen / GPU (i915) | ✅ should light up |
| Wacom digitizer (pen) | ✅ works as touch input |
| Halo keyboard surface | ⚠️ acts as a giant touchpad (no typing — v2 IME needed) |
| WiFi/BT (brcmfmac) | ✅ needs `firmware-brcm80211`-equivalent blobs (bundled in initrd) |
| Battery/charger | ✅ BQ27xxx + BQ25890 drivers |
| Sound | ❓ CHT_YOGABOOK machine driver present; test after boot |
| Camera, LTE | ❌ not supported |

**Keep a USB keyboard plugged in for the Android setup wizard** (WiFi sign-in, account).
Screen rotation may need the auto-rotate toggle in quick settings.

## 5. Install to eMMC (dual-boot with Windows)
1. In the live session, open GRUB's second entry (`Installation`) or the installer app.
2. Target the eMMC (`mmcblk…`/`sda…`) — the `Install` option creates an ext4 data image next to the ISO files if installing to the USB stick's own partition (frugal install), or wipes a chosen partition.
3. **Windows stays bootable** if you pick a free partition rather than wiping the disk; the installer adds a GRUB entry.
4. Reboot without the stick, hold Volume Up → pick the new *Bliss OS* entry.

## 6. Troubleshooting
- **Black screen on boot:** at the GRUB menu press `e`, add `video=DSI-1:1200x1920@60` or `i915.modeset=0` (diagnostic only) to the `linux` line.
- **No boot menu at all:** USB wasn't flashed in DD mode, or Secure Boot is still on.
- **Digitizer dead but screen works:** kernel booted with wrong DMI; check `adb shell dmesg | grep -i wacom` and report in the repo.
- **Boot loop:** try the `Safe mode` GRUB entry, then `adb logcat` via USB debugging.
