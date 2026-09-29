# Yoga Book (YB1-X91F) × Bass OS 16.9.7

Custom Android for the **Lenovo Yoga Book YB1-X91F** (Windows model, Cherry Trail x5-Z8550):
a **Bliss/Bass 16.9.7 (Android 13, Android-x86)** ISO with a Yoga-Book-specific kernel
built from [`jekhor/yogabook-linux-kernel`](https://github.com/jekhor/yogabook-linux-kernel)
(halo keyboard Goodix controller, Wacom EMR digitizer, battery/charger, KXCJ9 sensors,
RT5645 audio), rebuilt with Android's binder/ashmem config and injected into the ISO
(kernel + initrd modules + ramdisk modules).

Everything builds on **GitHub Actions** — your laptop is only used to push and download.

```
jekhor kernel (yogabook_defconfig) ──▶ + Android fragment (binder, uinput, ext4/squashfs…)
        │                                        │
        ▼                                        ▼
   bzImage + modules ────────────▶ repack Bliss 16.9.7 ISO (kernel, initrd, ramdisk)
                                                 │
                                                 ▼
                              YogaBook-BassOS-16.9.7-<date>-x86_64.iso  (artifact/release)
```

## Quick start

```bash
# 1. Create an empty repo on github.com (public, e.g. "yogabook-bass"), then:
git init && git add -A && git commit -m "Yoga Book Bass OS 16.9.7 build pipeline"
git remote add origin https://github.com/<you>/yogabook-bass.git
git push -u origin main

# 2. Watch it build (Actions tab) — kernel build ≈45–75 min on free runners.
# 3. Grab the ISO from Actions artifacts (or Releases if <2 GiB).
# 4. Flash with Rufus/Etcher (DD mode) to a USB stick, boot the Yoga Book
#    holding Volume Up, pick USB, choose "Bliss OS ..." (grub "Install" entry
#    installs to eMMC/SD).
```

## What's in the kernel fragment (`kernel/yogabook-android.fragment`)

| Area | Config |
|---|---|
| Android runtime | `ANDROID_BINDER_IPC/_FS/_DEVICES` (binder, hwbinder, vndbinder), `PSI`, `MEMCG` |
| Live boot | SQUASHFS (xz/lz4/zstd), ISO9660/Joliet, loop, ext4, vfat, EFI stub |
| Graphics | i915 built-in, SIMPLEDRM fallback, fbcon |
| Yoga Book input | `INPUT_UINPUT` (HaloKeyboard userspace daemon), GOODIX, HIDRAW/UHID |
| Audio | BYT/CHT RT5645 machine drivers as modules (SST path) |
| Yoga Book platform | inherited from `yogabook_defconfig` untouched (battery, charger, Wacom, sensors) |

**Known limits (v1):** Halo keyboard renders but Android has no IME daemon — typing still
needs the USB keyboard for setup (same as jekhor's Linux instructions). Sound, rotation,
autosleep untested until first real-hardware boot. Camera and LTE (X91L only) unsupported.

### Why not a from-scratch AOSP build?

A full Bass OS source build needs 16 cores / 32 GB RAM / 500–700 GB disk and Ubuntu 22.04
(source: bass-os README). This machine (i7-7600U, 16 GB, Windows + 77 GB free) can't hold
the source, let alone build it. The injection approach gives you the same end result — a
Bass-16.9.7-based ISO with Yoga Book drivers — while building entirely on GitHub runners.

## Files

```
.github/workflows/build-yogabook-bass.yml   CI: ISO download → kernel build → repack → upload
build-kernel.sh                             kernel build (jekhor tree + Android fragment)
kernel/yogabook-android.fragment            config fragment merged on yogabook_defconfig
repack-iso.sh                               kernel/modules/firmware injection + ISO rebuild
scripts/fetch-base-iso.sh                   standalone base-ISO fetch (manual/local builds)
```

## Roadmap

1. **v1 (this repo)** — bootable ISO, core hardware up (screen, touch, WiFi/BT, battery, digitizer). Halo keyboard shows as a big touchpad (Android treats it as such).
2. **v2** — HaloKeyboard IME daemon ported from jekhor's `touch-keyboard` userspace code → Android IME service + per-key haptics.
3. **v3** — audio bring-up (SST + RT5645 UCM from `alsa-ucm-conf-yogabook`), auto-rotation, tablet UX.
4. **v4** — upstream Bass OS licensing route (Bliss Co-Labs) for official Bass addons, OTA, kiosk mode.
