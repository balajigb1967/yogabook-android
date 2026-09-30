# Flashing & First Boot — Yoga Book YB1-X91F

## ⚡ One-touch install to SD card (NO keyboard needed, Windows kept)
**You need: a microSD card, 8 GB+ (class 10/UHS recommended), inserted in the
Yoga Book's SD slot. Everything on the SD card is erased.**

1. Flash the ISO to USB (step 2 below) and plug it into the Yoga Book.
2. Insert the microSD card into the tablet.
3. Power on holding **Volume Up** → pick USB.
4. **Do nothing.** The default GRUB entry (3 s) starts the guarded
   auto-installer, which now targets the **SD card**: it erases the SD,
   installs Android + GRUB on it with a persistent ext4 data partition, and
   **powers the tablet off by itself**. **Windows on eMMC is never touched.**
5. Remove the USB stick, keep the SD card in, power on →
   pick the **SD entry** in the Volume-Up boot menu → Android boots from SD.
   The SD card carries its own GRUB: **Android** is the default (1 s), with an
   opt-in *Install to eMMC (WIPES WINDOWS)* entry below it.
   (If the firmware menu doesn't list SD, boot the USB stick's "Live boot"
   entry once and we'll add an eMMC chainload entry.)

Multi-boot summary: **Volume-Up menu = OS picker** — SD entry → Android,
eMMC/Windows entry → Windows. Switching needs no keyboard.

### Other GRUB entries on the stick
- **Live boot (no install)** — try Android without installing anything
- **WIPE eMMC & install Android** — opt-in only; **erases Windows** and makes
  the tablet Android-only (10 s abort window)
- **Bliss original menu (debug)** — the stock BlissOS menu (iso-scan boot
  paths); useful only if the Yoga Book entries ever misbehave

All installs are **full wipes of their target** (new partition table + old
boot signatures zeroed) — no leftovers survive, and it only runs after the
DMI/eMMC guards pass and the 10-second on-screen abort window expires.

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
- **SD card (default):** Android + persistent data on the card; Windows
  untouched. Re-run the installer any time to re-wipe/reinstall the SD.
- **eMMC (opt-in via GRUB entry):** wipes Windows, Android-only tablet.
- **Live boot:** nothing installed; user data resets each boot unless you
  add a persistence option later.

## 6. Troubleshooting
### USB stick not detected in the boot menu (most common YB1 issue)
> **X91F note:** unlike the Android X90 model, the X91F BIOS has **no
> "USB Host Mode" toggle** — its micro-USB port is always host. Skip any
> advice about enabling it.

1. **BIOS → Boot tab:** Boot Mode = **UEFI**, Boot Priority = **UEFI First**,
   and **USB Boot = Enabled** if present. (Security → Secure Boot = Disabled.)
2. **Verify the DD write on Windows:** a correct DD flash makes the stick show
   up *shrunken (~2.9 GB)* with odd/unformattable partitions — normal. If you
   can browse the ISO files like a normal drive, it was written in ISO mode →
   re-flash with Rufus in **DD Image mode**.
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
3. Guard output: DMI check (`YB1-X91F/L`, `YB1-X90F/L`) + target scan — a
   non-Yoga-Book machine prints `[YB] not a Yoga Book` and live-boots instead
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
