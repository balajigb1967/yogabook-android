# Yoga Book Sensors

Yoga Book Sensors supplies the userspace sensor classification required by the
Lenovo Yoga Book YB1-X91L. The tablet exposes four identically named HID
accelerometers across two sensor hubs. Desktop rotation services need to know
which accelerometers belong to the display and which belong to the base. The
tablet also exposes an SX9310 capacitive proximity sensor whose hardware near
threshold must be supplied to `iio-sensor-proxy` through hwdb.

The package also replaces thermald's unusable ACPI-generated policy on this
model. That policy references `STR0` and `STR2`, whose firmware temperatures
are invalid. The replacement discovers and validates the actual coretemp,
PNIT, battery, charger, and cooling-device interfaces at service startup before
writing an ephemeral configuration under `/run`.

The project and Debian package are both named `yogabook-sensors`.

## Scope

This package contains only:

- a udev rule that adds the platform instance ID to the sensor hwdb key;
- X91L-scoped display/base accelerometer classifications;
- physically established display and base accelerometer mount matrices;
- the X91L SX9310 proximity near threshold reported by the kernel driver.
- a DMI-restricted thermald policy generated from validated live sysfs paths;
- CPU and PNIT control at 75 C with 3 C recovery hysteresis;
- battery charging control at 45 C and charger control at 70 C.

It deliberately contains no keyboard, pen, backlight, audio, firmware, camera,
kernel, or display-touchscreen policy. It never adds an automatic shutdown
action. The kernel's existing hardware-critical protection remains unchanged.
`iio-sensor-proxy` consumes the resulting udev properties and is recommended
rather than bundled.

## Build and test

Install the build dependencies:

```bash
sudo apt install debhelper devscripts libxml2-utils systemd thermald udev
```

Run the isolated hwdb and udev tests:

```bash
make test
```

Build the Debian package:

```bash
make deb
```

## Install

```bash
sudo apt install ../yogabook-sensors_1.0.0-8_all.deb
sudo reboot
```

After reboot, `udevadm info` must report `ACCEL_LOCATION=display` and an
identity mount matrix for instances `.10` and `.19`, `ACCEL_LOCATION=base`
with the base mount matrix for `.11` and `.20`, and `monitor-sensor --accel`
must follow physical display rotation. The SX9310 device must report
`PROXIMITY_NEAR_LEVEL=96`, and SensorProxy must expose proximity support.

`systemctl status thermald` must show thermald running with
`/run/thermald/yogabook-thermal-conf.xml`. The policy starts CPU throttling at
75 C, below the verified 90 C core critical limit. It reduces charging only if
the battery reaches 45 C or charger reaches 70 C, and releases cooling after a
3 C recovery margin. Check battery percentage, charging state, and both power
supply temperatures before manually changing any charging state.

See [ATTRIBUTION.md](ATTRIBUTION.md) and [LICENSE](LICENSE) for provenance and
licensing.
