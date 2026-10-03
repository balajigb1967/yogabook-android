# Yoga Book Camera

Yoga Book Camera is the userspace camera-integration project for the Lenovo
Yoga Book YB1-X91L. Its primary acceptance target is a usable front-facing
OV2740 camera for video meetings. The rear OV8858 camera is a separate 8 MP
sensor and does not substitute for the front camera.

## Current status

### Automated and transport status

The project contains an experimental raw Bayer userspace ISP and Debian
package. On the physical YB1-X91L it has proven:

- continuous front OV2740 Bayer10 capture and 1280x720 browser output, with
  runtime negotiation of the current BGGR10 and previous GRBG10 kernel ABIs;
- continuous rear OV8858 BGGR10 capture with per-row stride removal;
- automatic sensor exposure/gain and userspace white balance convergence;
- GPU color-shading correction and temporal/spatial denoising;
- separate front and rear V4L2 endpoints usable by Chromium applications;
- automatic one-at-a-time AtomISP switching from the application's camera
  selector.

### Physical acceptance

It is not yet a stable release. Front-camera color and noise still need final
physical tuning against human skin in several lighting conditions. The rear
camera transport and sensor test pattern are proven, and its black frame was
traced to incorrect kernel digital-gain programming. A corrected real 8 MP
still requires physical color, focus and detail acceptance. See
[docs/ACCEPTANCE.md](docs/ACCEPTANCE.md).

See [docs/STATUS.md](docs/STATUS.md) for established evidence,
[docs/CALIBRATION.md](docs/CALIBRATION.md) for the calibration method and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for subsystem ownership, and
[docs/KERNEL-CONTRACT.md](docs/KERNEL-CONTRACT.md) for the required kernel and
runtime interface. The
inspected official package is documented in
[docs/WINDOWS-DRIVER-EVIDENCE.md](docs/WINDOWS-DRIVER-EVIDENCE.md).

## Repository scope

This repository will own:

- a safe userspace AIQ/3A or equivalent image-control implementation;
- user-supplied Lenovo tuning inspection and staging tools;
- integration with V4L2, PipeWire and meeting applications;
- camera-specific packaging and operational documentation.

It deliberately does not own:

- OV2740, OV8858 or AtomISP kernel changes, which remain in
  `Yoga-Book-Linux-Kernel`;
- general hardware acceptance, which remains in `Yoga-Book-Validator`;
- redistribution of Lenovo or Intel proprietary tuning/software without a
  verified license;
- an older AtomISP DKMS replacement for the newer in-tree kernel driver.

## Inspecting Lenovo tuning

The tuning file is not included. After obtaining it from Lenovo's official
Yoga Book Windows driver package, inspect it locally:

```bash
tools/inspect-aiqb.sh /path/to/OV2740_CJAE533_CHT.cpf
```

The command validates the AIQB signature, Yoga Book OV2740 description, exact
size and the hash of the physically inspected Lenovo artifact. To keep an
ignored private working copy for research:

```bash
tools/stage-lenovo-tuning.sh /path/to/OV2740_CJAE533_CHT.cpf
```

Staging does not install or activate the file because there is not yet a safe
runtime consumer.

## Development

```bash
sudo apt install binutils coreutils debhelper make shellcheck
make test
make package
```

## Runtime

The package prepares camera integration only on a DMI-matched YB1-X91L and
consumes the sensor-matched raw formats exposed by AtomISP. It exposes
`Front Camera` and `Rear Camera` without changing a kernel module parameter.
Choose either device directly in Google Meet, Chromium or another V4L2 camera
application. The service observes which endpoint the application keeps open
and switches the single physical AtomISP pipeline automatically. The front
camera is the default until an application selects the rear camera.

The browser-facing endpoints remain discoverable while unused, but the raw
sensor, AtomISP and image-processing pipelines stop after three seconds with
no external camera client. Opening either endpoint resumes processing. A
service start establishes 1280x720 YUYV producer caps before desktop camera
discovery, then locks them after both writers are active. This prevents the
loopbacks' default BGR4 format from winning a boot-time race without turning an
unowned `exclusive_caps` endpoint capture-only. Pipeline errors exit nonzero
and trigger the bounded systemd restart policy instead of silently leaving
stale camera devices. A thermal
gate stops processing at 85 C and does not restart it until the
hottest valid system thermal-zone reading is at or below 75 C. The systemd
unit additionally caps the processor at 175% CPU, 384 MiB memory and 64 tasks,
with low scheduling weight so camera work cannot monopolize the tablet.

The diagnostic controller performs the same in-place handoff without
restarting the browser-facing endpoints:

```bash
yogabook_camera_control.py select front
yogabook_camera_control.py select rear
yogabook_camera_control.py status
yogabook_camera_control.py capture "$HOME/Pictures/yogabook-rear.jpg"
```

Only the selected sensor streams through AtomISP2401; the two named endpoints
are application choices, not simultaneous physical streams. No release should
claim complete camera support until every physical gate in the acceptance
document passes.
