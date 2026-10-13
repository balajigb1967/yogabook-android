# Yoga Book ROM — Android 16 (LineageOS 23.2) for Lenovo Yoga Book YB1-X90F/X91F/X91L

A custom Android 16 ROM for the **Lenovo Yoga Book** (Intel Atom x5-Z8550, Cherry Trail),
built **from scratch on pure LineageOS 23.2 sources** — no third-party ROM base, no
licensing watermark, no "unlicensed version" nags.

The ROM is built from the official LineageOS `device/mainline/generic` x86_64 tree
(mainline Linux kernel, custom first-stage init, hardware detection service) plus a
Yoga Book device overlay in this repository.

## Hardware status

| Component | Status | How |
| :--- | :---: | :--- |
| Boot, display, touchscreen | ✅ Works | Mainline kernel + goodix driver |
| Wi-Fi (BCM4356) & Bluetooth | ✅ Works | `brcmfmac` + mainline BT |
| Auto-rotation / sensors | ✅ Works | IIO sensors + mainline hid-sensors |
| **Halo keyboard + haptics** | 🛠 Enabled here | Goodix surface → `touch_keyboard_handler` → uinput (ported to Android init) |
| **Audio (RT5677)** | 🛠 Enabled here | `cht_rt5677` ASoC machine-driver patch + TinyHAL |
| **Camera (AtomISP)** | ⚠ Best effort | `CONFIG_VIDEO_ATOMISP` staging driver enabled + sensor patches; Cherry Trail cameras are historically hard — logs are captured for diagnosis |
| **LTE (YB1-X91L, Intel XMM7260)** | ⚠ Experimental | `cdc_mbim`/`cdc-wdm` kernel drivers + diagnostics; a full Android RIL for XMM7260 does not exist yet — see [docs/hardware-status.md](docs/hardware-status.md) |
| "Unlicensed version" notice | 🗑 Gone | Pure LineageOS build, own branding, no third-party watermark |

## ISO features (what you flash to the SD card / USB stick)

* **rEFInd boot manager with touch & mouse support** — large touch-friendly icons,
  portrait-friendly resolution, no keyboard needed. GRUB BIOS fallback kept for
  legacy machines.
* **Multi-kernel boot menu** — each ISO ships several kernel versions
  (Yoga-Book-patched default + mainline + LTS fallback). Pick with a tap.
* **Boot & hardware failure log capture** — every boot writes `dmesg`, early init
  logs, logcat, module probe results, USB/PCI/ACPI device lists into `/bootlogs/`
  on the flash media. If the screen goes black, pull the SD card into any PC and
  read `/bootlogs/`.

## Building

Everything is scripted; the same script runs locally (WSL2/Ubuntu, ~140 GB free disk)
and on a self-hosted GitHub Actions runner. Free GitHub-hosted runners are **too
small** for an Android source build (14 GB disk vs ~120 GB needed).

```bash
# On Ubuntu / WSL2 with >=140 GB free disk and >=16 GB RAM:
./scripts/build-local.sh            # sync sources, build, produce ISO(s) in ./dist
```

Outputs land in `dist/`:

* `YOGABOOK-x86_64-<version>-live.iso` — bootable live/install ISO (rEFInd, multi-kernel)
* `bootlogs-readme.txt` — how log capture works

### CI (self-hosted runner)

Register your own Linux box as a self-hosted runner with labels
`[self-hosted, linux, x64]` and run the **build-iso** workflow. See
[docs/building.md](docs/building.md).

## Flashing

See [docs/flash-guide.md](docs/flash-guide.md) — rEFInd is fully touch-driven, no
physical keyboard required. Google Play certification notes are in
[docs/gapps.md](docs/gapps.md).

## Repository layout

```
manifest/local_manifests/   Pins LineageOS 23.2 + mainline generic tree + kernel sources
device/yogabook/x86_64/     Yoga Book device overlay (kernel config, audio, input, ISO task)
device/yogabook/halo-keyboard/  Halo keyboard handler, ported to Android (soong)
device/yogabook/diagnostics/    Boot/hardware log capture service
scripts/                    One-command build, kernel fetch, ISO packaging
docs/                       Flashing, hardware status, building guides
.github/workflows/          CI for self-hosted runners
```

## Credits

* [The LineageOS Project](https://lineageos.org) — Android 16 platform & the
  mainline generic x86_64 device tree.
* [Yauhen Kharuzhy (jekhor)](https://github.com/jekhor) — Yoga Book Linux drivers
  (Halo keyboard handler, RT5677 audio work, platform quirks).
* Chromium OS touch keyboard handler — upstream of the Halo keyboard daemon.

Licensed Apache-2.0 (our overlay code; upstream components keep their own licenses).
