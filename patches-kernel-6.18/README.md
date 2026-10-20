# Lenovo Yoga Book (YB1-X90F / YB1-X91F / YB1-X91L) Kernel 6.18 Backport Series

This directory contains the complete backport patchset to bring official Lenovo Yoga Book hardware drivers onto **Linux Kernel 6.18** (such as [android-generic/kernel-zenith](https://github.com/android-generic/kernel-zenith) branches `6.18` / `6.18_android-x86`).

## Patch Series Overview

| Patch File | Subsystem & Component | Description & Target Files |
| :--- | :--- | :--- |
| `0001-ASoC-Intel-Add-Cherry-Trail-RT5677-machine-driver.patch` | **Audio (ASoC)** | Adds Maurizio Casciano's Cherry Trail RT5677 machine driver (`sound/soc/intel/boards/cht_rt5677.c`, `Kconfig`, `Makefile`). Supports dual speakers, stereo digital mics, TS3A227E jack detection, MCLK/PLL configuration, and SOF/SST mutual exclusivity. |
| `0002-ASoC-Intel-cht-Add-Yoga-Book-RT5677-machine-entry.patch` | **Audio (ACPI Match)** | Maps ACPI device `10EC5677` to machine driver `cht-rt5677` and SOF topology `sof-cht-rt5677.tplg` in `sound/soc/intel/common/soc-acpi-intel-cht-match.c`. |
| `0003-platform-x86-x86-android-tablets-Describe-Yoga-Book-haptics.patch` | **Haptics (DRV2604)** | Attaches board software nodes for `DRV2604:00` and `DRV2604:01` with Cherryview GPIO enable lines in `drivers/platform/x86/x86-android-tablets/lenovo.c`. |
| `0004-platform-x86-x86-android-tablets-Add-Yoga-Book-TS3A227E.patch` | **Audio Jack (TS3A227E)** | Instantiates I2C client for TS3A227E on bus I2C1 (0x3b) with GPIO interrupt in `drivers/platform/x86/x86-android-tablets/lenovo.c`. |
| `0005-platform-x86-x86-android-tablets-Add-Yoga-Book-audio-GPIOs.patch` | **Audio Amplifiers** | Registers RT5677 GPIO provider softnodes for GPIO2 (second speaker boost) and GPIO4 (headphone enable). |
| `0006-Input-drv260x-Fix-suspend-and-resume-sequencing.patch` | **Haptics Core** | Fixes suspend/resume sequencing, device close restore, and regulator enablement in `drivers/input/misc/drv260x.c`. |
| `0007-power-supply-core-Honor-supplied-from-with-CONFIG_OF.patch` | **Fast Charging** | Upstream patch by Sebastian Reichel in `drivers/power/supply/power_supply_core.c`. Enables `supplied-from` notifications on x86 platforms when `CONFIG_OF=y`, waking TI BQ25892 from default 500mA boot rate to full fast-charging current. |
| `0008-xhci-Restore-SSIC-state-on-the-Lenovo-Yoga-Book.patch` | **LTE Modem USB Port** | DMI-scoped quirk restoring Cherry Trail xHCI SSIC registers and link retraining for Intel XMM7260 modem in `drivers/usb/host/xhci-pci.c` and `xhci-ring.c`. |
| `0009-platform-x86-Add-Cherry-Trail-XMM7260-power-driver.patch` | **LTE Modem Power** | Platform power sequencing driver (`INT34D0` ACPI device DSM + PMIC power sequence) in `drivers/platform/x86/intel/cht_modem.c`. |
| `0010-media-atomisp-allow-raw-Bayer-capture.patch` | **Camera (AtomISP)** | Enables continuous raw Bayer10 capture and runtime format negotiation in `drivers/staging/media/atomisp/`. |
| `0011-media-i2c-Add-WV517S-lens-actuator-driver.patch` | **Camera (Actuator)** | Adds WV517S lens voice-coil actuator driver for rear 8MP autofocus in `drivers/media/i2c/wv517s.c`. |

## How to Apply to Kernel 6.18

From your kernel source tree (e.g. `kernel-zenith` on branch `6.18_android-x86`):

```bash
git am --3way /path/to/patches-kernel-6.18/*.patch
```

Or run the automated helper script:

```bash
# In Bash:
./scripts/apply-kernel-patches.sh /path/to/kernel-zenith

# Or in Python:
python scripts/apply_kernel_618_patches.py /path/to/kernel-zenith
```

## Required Kernel 6.18 Config Symbols

Merge the provided fragment [yogabook.config](file:///c:/Yogabook/device/yogabook/YOGABOOK_x86_64/configs/kernel/yogabook.config):

```ini
CONFIG_SND_SOC_INTEL_CHT_RT5677_MACH=y
CONFIG_SND_SOC_RT5677=y
CONFIG_SND_SOC_TS3A227E=y
CONFIG_INPUT_DRV260X_HAPTICS=y
CONFIG_TOUCHSCREEN_GOODIX=y
CONFIG_INPUT_WACOM=y
CONFIG_INPUT_UINPUT=y
CONFIG_CHARGER_BQ25892=y
CONFIG_INTEL_SOC_PMIC_CHTWC=y
CONFIG_INTEL_ATOMISP=y
CONFIG_VIDEO_ATOMISP=y
CONFIG_VIDEO_OV2740=y
CONFIG_VIDEO_OV8858=y
CONFIG_INTEL_XMM7260=y
CONFIG_USB_NET_CDC_MBIM=y
CONFIG_BMC150_ACCEL=y
CONFIG_HID_SENSOR_HUB=y
```
