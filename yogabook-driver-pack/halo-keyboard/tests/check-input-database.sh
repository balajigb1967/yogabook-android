#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause

set -Eeuo pipefail

root=${1:?project root is required}
temporary_base=${TMPDIR:-/var/tmp}
temporary_root=$(mktemp -d "$temporary_base/halo-keyboard-hwdb.XXXXXX")

cleanup() {
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

install -D -m 0644 "$root/udev/61-halo-keyboard.hwdb" \
	"$temporary_root/etc/udev/hwdb.d/61-halo-keyboard.hwdb"

systemd-hwdb --root="$temporary_root" --strict update
udevadm verify --no-style --no-summary "$root/udev/60-halo-keyboard.rules"

x91l_match=$(systemd-hwdb --root="$temporary_root" query \
	'evdev:name:Wacom HID 169 Pen:dmi:bvnLENOVO:pnLenovoYB1-X91L:' || true)
if grep -Fq 'LIBINPUT_CALIBRATION_MATRIX=' <<<"$x91l_match"; then
	echo 'Wacom calibration must remain neutral for dynamic display mapping' >&2
	exit 1
fi

x90_match=$(systemd-hwdb --root="$temporary_root" query \
	'evdev:name:Wacom HID 169 Pen:dmi:bvnLENOVO:pnLenovoYB1-X90L:' || true)
if grep -Fq 'LIBINPUT_CALIBRATION_MATRIX=' <<<"$x90_match"; then
	echo 'Wacom calibration unexpectedly matches unvalidated YB1-X90L' >&2
	exit 1
fi

display_match=$(systemd-hwdb --root="$temporary_root" query \
	'evdev:name:HDP0001:00 2ABB:8102:dmi:bvnLENOVO:pnLenovoYB1-X91L:' || true)
if grep -Fq 'LIBINPUT_CALIBRATION_MATRIX=' <<<"$display_match"; then
	echo 'Wacom calibration unexpectedly matches the display touchscreen' >&2
	exit 1
fi

tablet="$root/libwacom/wacom-yoga-book.tablet"
grep -Fxq 'Name=Wacom HID 169' "$tablet"
grep -Fxq 'ModelName=WCOM0019' "$tablet"
grep -Fxq 'DeviceMatch=i2c|056a|0169' "$tablet"
grep -Fxq 'IntegratedIn=System' "$tablet"
grep -Fxq 'Stylus=true' "$tablet"
grep -Fxq 'Touch=false' "$tablet"

echo 'input database: PASS'
