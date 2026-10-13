# Flashing & booting guide (touch only — no physical keyboard needed)

The ISO is a hybrid image: it boots with **rEFInd** on UEFI machines (the Yoga
Book's firmware is UEFI) and falls back to GRUB on legacy BIOS machines. rEFInd
is configured with large icons and touch enabled — **tap the icon to boot**.

## 1. Write the ISO to your SD card / USB stick

On Windows: use [Rufus](https://rufus.ie) (write in **ISO mode**, GPT/UEFI) or
[Ventoy](https://www.ventoy.net). On Linux/macOS:

```bash
sudo dd if=YOGABOOK-x86_64-*-live.iso of=/dev/sdX bs=4M status=progress && sync
```

Replace `/dev/sdX` with your card/stick device (double-check!).

> **USB stick / SD card only** — the ISO boots via its GPT/FAT partition, which
> is exactly what `dd`/Rufus write to removable media. Booting from a CD/DVD
> is not supported.

## 2. Boot from it

1. Plug the card into the Yoga Book, power on, tap the screen repeatedly while
   pressing the power button; if the boot menu does not appear, hold **Volume Up**
   while powering on (Lenovo OneKey recovery / boot menu) and pick the USB device.
2. **rEFInd appears** — a row of big icons. Tap the kernel entry you want:
   * **Yoga Book kernel (default)** — patched mainline with Halo keyboard, RT5677
     audio and AtomISP camera drivers. Use this one.
   * **Mainline (latest)** — vanilla latest mainline kernel.
   * **LTS fallback** — conservative LTS kernel for rescue/diagnostics.
3. Android live mode starts. User data lives in RAM by default (nothing is
   written to your disk until you install).

Every rEFInd entry has an arrow below the icon for sub-options (debug, console,
copy-to-RAM). Tap the small "info" area or use the second row for those.

## 3. Install to the internal eMMC (optional)

The LineageOS mainline generic installer target writes `system`, `vendor` and
userdata partitions with GPT names; see `docs/` in the source tree. **Back up
first** — this device's eMMC is soldered.

## 4. If something breaks: read the logs

The ROM automatically writes:

* `bootlogs/dmesg.log`, `bootlogs/logcat.log` — live kernel + Android logs
* `bootlogs/hwreport-*.txt` — hardware enumeration (PCI/USB/input/modules),
  taken at boot and every 10 minutes
* early-init logs copied from `/metadata`

…into `bootlogs/` **on the flash card itself** (when the card is writable) and
into internal storage (`bootlogs/` in the user data, reachable over MTP).

If the device won't boot or a hardware device is missing, pull the card into any
PC and read `bootlogs/`. Attach those files when reporting an issue.
