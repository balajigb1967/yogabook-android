# Flashing & First Boot — Yoga Book YB1-X91F

## ⚠️⚡ One-touch install to eMMC (DEFAULT — ERASES WINDOWS)
**Read this first: the default GRUB entry wipes the internal 64 GB eMMC —
**Windows and all its data are erased** — and installs Android there. This is
what you asked for (no keyboard, SD slot not enumerating). The tablet becomes
**Android-only**.**

**Why default eMMC:** your SD slot didn't enumerate (`no removable SD card
found`), and GRUB cannot listen to the volume buttons (firmware-only GPIO) —
so the keyboardless path is a **zero-input default**: pick USB in the
Volume-Up firmware menu, and the eMMC install runs by itself.

1. Flash the ISO to USB (step 2 below) and plug it into the Yoga Book.
2. Power on holding **Volume Up** → pick USB.
3. **Do nothing.** Default entry (5 s): `INSTALL ANDROID TO eMMC (ERASES
   WINDOWS!)`. It identifies the machine (refuses on non-Yoga-Books), then
   shows a **10-second `POWER OFF NOW TO ABORT`** window — hold the power
   button to force-off if you change your mind.
4. Partition / format / copy run on screen, then the tablet **powers off
   itself**. Remove the stick.
5. Power on → Android boots from eMMC. (Windows is gone. To ever get it
   back you must reinstall it from USB.)

### Other GRUB entries on the stick (arrow keys need a USB keyboard; without
one, the default runs)
- **AUTO-INSTALL to SD card (keeps Windows)** — the old safe path, kept for
  when an SD card enumerates
- **Live boot (no install)** — try Android without installing anything
- **Bliss original menu (debug)** — the stock BlissOS menu

All installs are **full wipes of their target** (new partition table + old
boot signatures zeroed). The eMMC wipe only runs after a positive Yoga Book
DMI match and the 10-second on-screen abort window.

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
**YB1-X91F reality check (field-tested):** this tablet's firmware enumerates
**Rufus-ISO-mode** sticks reliably; **Rufus-DD-mode sticks are NOT detected**
in its boot menu regardless of the ISO's embedded boot records. Use ISO mode.

**Rufus settings:**

| Setting | Value |
|---|---|
| Boot selection | the YogaBook ISO |
| Partition scheme | **GPT** |
| Target system | **UEFI (non CSM)** |
| At the "ISOHybrid" prompt | **ISO Image mode** (not DD — see note above) |

After flashing Windows will ask to format the stick — **Cancel, never format**.

*(DD mode / Etcher raw-write works on generic PCs and with the "Use a device"
route, but the YB1's own boot menu skips DD sticks — ISO mode it is.)*

- Verify SHA256 against the build output if you like.

## 3. Boot from USB
1. Connect the OTG hub → USB stick (+ USB keyboard).
2. Power on holding **Volume Up** → pick the USB drive in the boot menu.
3. The **GRUB menu** appears — `Yoga Book — AUTO-INSTALL to SD card` is the
   default (3 s countdown). Pick **Live boot (no install)** to just try it,
   or **Bliss original menu (debug)** for the stock BlissOS menu.

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

## 5. Install target options
- **eMMC (default):** Android-only tablet; Windows erased. Re-run the
  installer any time to re-wipe/reinstall.
- **SD card (GRUB entry):** Android + persistent data on the card; Windows
  untouched — only works if the card enumerates (yours currently does not).
- **Live boot:** nothing installed; user data resets each boot unless you
  add a persistence option later.

## 6. Troubleshooting
### USB stick not detected in the boot menu (most common YB1 issue)
> **X91F note:** unlike the Android X90 model, the X91F BIOS has **no
> "USB Host Mode" toggle** — its micro-USB port is always host. Skip any
> advice about enabling it.

1. **BIOS → Boot tab:** Boot Mode = **UEFI**, Boot Priority = **UEFI First**,
   and **USB Boot = Enabled** if present. (Security → Secure Boot = Disabled.)
2. **Verify the flash on Windows:** a Rufus **ISO-mode** stick shows the ISO
   contents as files — that is exactly what we want (the YB1 firmware only
   enumerates ISO-mode sticks; DD-mode sticks are invisible in its boot menu).
3. **Skip the BIOS entirely (recommended, Windows still installed):**
   hold **Shift + Restart** in Windows → *Troubleshoot → Advanced options →
   **Use a device*** → pick the USB stick. Windows' own boot manager launches
   our ISO — no Volume-Up menu needed.
4. Plug the stick in **before** power-on, through a **powered OTG hub**
   (the micro port is weak — unpowered adapters often fail to enumerate sticks).
5. Still nothing? Try a single OTG adapter instead of a hub, or another stick
   (the YB1 is picky about USB controllers).

- **"Kernel panic - not syncing: No working init found"** (purple screen):
  the initrd could not run its `/init`. Older builds had two causes, both
  fixed: an lz4-packed initrd (kernels lacking RD_LZ4), and — the real
  killer — the repacked initrd carried **no `/bin/sh`** for the injected
  installer shim (stock Bliss initrds ship only `/bin/busybox`). Builds
  after 2026-09-30 integrity-gate the initrd at build time (gzip test,
  `/init`, `/bin/sh`, modules present) and are QEMU-validated to reach the
  Bliss banner. **Reflash the newest ISO.** If it appears **without** the
  USB stick inserted, the eMMC install never completed.

### What a correct auto-install run looks like (new builds)
1. GRUB: 3 s countdown on the default **AUTO-INSTALL to SD** entry
2. Kernel messages scroll (no quiet), then `[YB] auto-installer starting...`
   (the shim first loads USB-storage/SD/HID modules — silent, a few seconds)
3. Guard output: either nothing (positive Yoga Book DMI match) or
   `[YB] DMI inconclusive - continuing, SD card only` (safe: SD-only path
   never aborts on a missing ID; the **eMMC wipe** entry still refuses
   without a positive `YB1-X9xF`/`YB1-X9xL` match)
4. `[YB] MODE: install to SD card...` + `[YB] target device: mmcblkX`
   (or `[YB] no removable SD card found` → live boot, nothing harmed)
4. `!!!! AUTO-INSTALL: erasing ... POWER OFF NOW TO ABORT !!!!` (10 s window)
5. Partition/format/copy steps print to screen
6. `AUTO-INSTALL COMPLETE - powering off` → remove stick, power on

If any step fails it prints the reason and falls through to **live boot from
the stick** — Android still runs, eMMC untouched.

### Did the old (buggy) build wipe my Windows? Quick check
Power on **normally, no USB**: Lenovo logo → Windows boots = eMMC untouched.
Boot straight to the purple panic or a GRUB shell = the eMMC was re-partitioned;
Windows is gone but a fresh auto-install (new ISO) is unaffected — it wipes
and reinstalls anyway.
- **No boot menu at all:** USB wasn't flashed in DD mode, or Secure Boot is still on.
- **Digitizer dead but screen works:** kernel booted with wrong DMI; check `adb shell dmesg | grep -i wacom` and report in the repo.
- **Boot loop:** try the `Safe mode` GRUB entry, then `adb logcat` via USB debugging.
