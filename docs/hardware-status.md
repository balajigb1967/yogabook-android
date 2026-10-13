# Hardware status — Lenovo Yoga Book (YB1-X90F/X91F/X91L)

Base: LineageOS 23.2 / Android 16, `device/mainline/generic` (mainline Linux
kernel built from Debian mainline source).

| Component | Status | Notes |
| :--- | :---: | :--- |
| Boot / display / touchscreen | ✅ | Mainline + goodix (9-byte Yoga Book reports handled upstream in `goodix.c`) |
| Wi-Fi | ✅ | Broadcom **BCM4356** (`brcmfmac`, PCI 14e4:43ec), firmware from `linux-firmware` |
| Bluetooth | ✅ | Mainline BT stack |
| Auto-rotation | ✅ | IIO sensors / hid-sensor-hub |
| **Halo keyboard + touchpad** | 🛠 enabled | Goodix surface → `touch_keyboard_handler` → uinput (vendored, BSD). Starts after boot; layout = pc105. Haptics via DRV2604 (force-feedback events). |
| **Audio** | 🛠 enabled | Realtek **RT5677** codec + Intel SST. Upstream has the codec (`SND_SOC_RT5677`) but **not** the Cherry Trail machine driver, so the build applies the `cht_rt5677` ASoC machine-driver patch series (`SND_SOC_INTEL_CHT_RT5677_MACH`, supports YB1-X91F/L) plus the TS3A227E headset-switch driver. TinyHAL picks the first sink/source. |
| **Camera (AtomISP)** | ⚠ best effort | Cherry Trail cameras hang off the Intel IPU (`8086:22b8`). The **staging** `atomisp` driver (`CONFIG_VIDEO_ATOMISP`) is enabled plus the Yoga Book sensor/bridge patch series. Staging driver + firmware quirks ⇒ expect issues; `bootlogs/hwreport-*.txt` shows whether sensors probed. |
| **LTE (YB1-X91L)** | ⚠ experimental | The modem is an **Intel XMM7260** on the SSIC/xHCI bus. `cdc_mbim`/`cdc-wdm`/`option` drivers are enabled. Two hard parts remain: (1) firmware/ACPI power sequencing to make the modem enumerate as an MBIM function, and (2) Android has no XMM7260 RIL — data works only if the modem enumerates and a userspace manager (mbimcli/ModemManager-style) activates a session. Expect months-not-days; logs are captured to speed debugging. |
| Digitizer pen | 🛠 | Wacom I2C (`WCOM0019`, `wacom_i2c`) — mainline |
| "Unlicensed version" notice | 🗑 gone | Pure LineageOS build, no third-party ROM watermark |

## Where things live in the tree

* Halo keyboard: `device/yogabook/halo-keyboard/` (daemon, init rc, layouts)
* Audio: kernel config fragment + machine-driver patch applied by
  `scripts/apply-kernel-patches.sh`
* Camera/LTE: enabled in the same kernel config fragment; diagnostics in
  `device/yogabook/diagnostics/`
