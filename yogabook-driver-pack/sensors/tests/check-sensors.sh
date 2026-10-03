#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
temporary_base=${TMPDIR:-/mnt/DATA/tmp}
temporary_root=$(mktemp -d "$temporary_base/yogabook-sensors-hwdb.XXXXXX")

required_files=(
	LICENSE
	README.md
	debian/control
	debian/rules
	debian/yogabook-sensors.docs
	debian/yogabook-sensors.install
	debian/yogabook-sensors.postinst
	debian/yogabook-sensors.postrm
	libexec/generate-thermald-config.sh
	systemd/thermald.service.d/10-yogabook-policy.conf
	udev/61-yogabook-sensors.hwdb
	udev/61-yogabook-sensors.rules
)

for required_file in "${required_files[@]}"; do
	test -f "$root/$required_file"
done

for executable_file in \
	debian/rules \
	debian/yogabook-sensors.postinst \
	debian/yogabook-sensors.postrm \
	debian/tests/smoke \
	libexec/generate-thermald-config.sh \
	tests/check-sensors.sh \
	tests/check-thermald.sh; do
	test -x "$root/$executable_file"
done

grep -Fq 'GNU GENERAL PUBLIC LICENSE' "$root/LICENSE"
grep -Fxq 'Package: yogabook-sensors' "$root/debian/control"
grep -Fxq 'README.md' "$root/debian/yogabook-sensors.docs"
grep -Fq '61-yogabook-sensors.rules usr/lib/udev/rules.d' \
	"$root/debian/yogabook-sensors.install"
grep -Fq '61-yogabook-sensors.hwdb usr/lib/udev/hwdb.d' \
	"$root/debian/yogabook-sensors.install"
grep -Fq 'generate-thermald-config.sh usr/libexec/yogabook-sensors' \
	"$root/debian/yogabook-sensors.install"

cleanup() {
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

install -D -m 0644 "$root/udev/61-yogabook-sensors.hwdb" \
	"$temporary_root/etc/udev/hwdb.d/61-yogabook-sensors.hwdb"

systemd-hwdb --root="$temporary_root" --strict update
udevadm verify --no-style --no-summary \
	"$root/udev/61-yogabook-sensors.rules"

grep -Fq 'KERNELS=="HID-SENSOR-200073.10.auto", ENV{ACCEL_LOCATION}="display", ENV{ACCEL_MOUNT_MATRIX}="1, 0, 0; 0, 1, 0; 0, 0, 1"' "$root/udev/61-yogabook-sensors.rules"
grep -Fq 'KERNELS=="HID-SENSOR-200073.11.auto", ENV{ACCEL_LOCATION}="base", ENV{ACCEL_MOUNT_MATRIX}="0, 1, 0; -1, 0, 0; 0, 0, 1"' "$root/udev/61-yogabook-sensors.rules"
grep -Fq 'KERNELS=="HID-SENSOR-200073.19.auto", ENV{ACCEL_LOCATION}="display", ENV{ACCEL_MOUNT_MATRIX}="1, 0, 0; 0, 1, 0; 0, 0, 1"' "$root/udev/61-yogabook-sensors.rules"
grep -Fq 'KERNELS=="HID-SENSOR-200073.20.auto", ENV{ACCEL_LOCATION}="base", ENV{ACCEL_MOUNT_MATRIX}="0, 1, 0; -1, 0, 0; 0, 0, 1"' "$root/udev/61-yogabook-sensors.rules"

proximity=$(systemd-hwdb --root="$temporary_root" query \
	'sensor:modalias:acpi:STH9310::dmi:bvnLENOVO:pnLenovoYB1-X91L:' || true)
grep -Fqx 'PROXIMITY_NEAR_LEVEL=96' <<<"$proximity"

if systemd-hwdb --root="$temporary_root" query \
	'sensor:modalias:acpi:STH9310::dmi:bvnLENOVO:pnLenovoYB1-X90L:' |
	grep -Fq 'PROXIMITY_NEAR_LEVEL='; then
	echo 'proximity configuration unexpectedly matches YB1-X90L' >&2
	exit 1
fi

grep -Fq 'ATTR{[dmi/id]product_name}!="Lenovo YB1-X91L"' \
	"$root/udev/61-yogabook-sensors.rules"

echo 'Yoga Book sensor database: PASS'
