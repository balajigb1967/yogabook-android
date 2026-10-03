#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause

set -Eeuo pipefail

root=${1:?project root is required}

required_files=(
	libexec/ensure-backlight-minimum
	udev/60-halo-keyboard.rules
	udev/61-halo-keyboard.hwdb
	libwacom/wacom-yoga-book.tablet
	ATTRIBUTION.md
	LICENSE
	README.md
	systemd/halo-keyboard.service
	systemd/halo-keyboard-backlight.service
	config/hardware.csv
	config/touchpad.csv
	include/halo_keyboard/hardware_config.h
	src/hardware_config.cc
	debian/control
	debian/copyright
	debian/halo-keyboard.postinst
	debian/source/options
	tests/check-handler-config.sh
	tests/check-backlight-policy.sh
)

for file in "${required_files[@]}"; do
	[[ -s $root/$file ]] || {
		echo "missing required project file: $file" >&2
		exit 1
	}
done

grep -Fxq 'ExecStart=/usr/sbin/halo-keyboard-handler --config-directory /etc/halo-keyboard -m 1.0 -D 12' \
	"$root/systemd/halo-keyboard.service"
grep -Fxq 'ExecStartPre=-/usr/bin/udevadm settle --timeout=10' \
	"$root/systemd/halo-keyboard.service"
grep -Fq -- '--config-directory /etc/halo-keyboard' \
	"$root/systemd/halo-keyboard.service"
grep -Fxq 'CapabilityBoundingSet=' "$root/systemd/halo-keyboard.service"
grep -Fxq 'ProtectKernelTunables=true' "$root/systemd/halo-keyboard.service"
grep -Fxq 'RestrictNamespaces=true' "$root/systemd/halo-keyboard.service"
grep -Fxq 'CPUQuota=100%' "$root/systemd/halo-keyboard.service"
grep -Fxq 'MemoryMax=32M' "$root/systemd/halo-keyboard.service"
grep -Fxq 'TasksMax=16' "$root/systemd/halo-keyboard.service"
grep -Fxq 'StartLimitBurst=5' "$root/systemd/halo-keyboard.service"
grep -Fxq 'BindsTo=dev-halo_keyboard.device' \
	"$root/systemd/halo-keyboard.service"
grep -Fxq 'After=dev-halo_keyboard.device' \
	"$root/systemd/halo-keyboard.service"
grep -Fxq 'Restart=on-failure' "$root/systemd/halo-keyboard.service"
grep -Fq 'SYMLINK+="halo_keyboard"' "$root/udev/60-halo-keyboard.rules"
grep -Fq 'ENV{SYSTEMD_WANTS}+="halo-keyboard.service"' \
	"$root/udev/60-halo-keyboard.rules"
grep -Fq 'IsExpectedSourceDeviceError(error.code())' "$root/src/main.cc"
grep -Fq 'return expected_stop ? EXIT_SUCCESS : EXIT_FAILURE;' "$root/src/main.cc"
grep -Fxq 'ExecStart=/usr/libexec/halo-keyboard/ensure-backlight-minimum' \
	"$root/systemd/halo-keyboard-backlight.service"
grep -Fxq 'ReadWritePaths=/sys/class/leds/ybwmi::kbd_backlight/brightness' \
	"$root/systemd/halo-keyboard-backlight.service"
grep -Fq 'Package: halo-keyboard' "$root/debian/control"
grep -Eq '^ udev,$' "$root/debian/control"
grep -Eq '^ libwacom-common,$' "$root/debian/control"
grep -Eq '^ systemd,$' "$root/debian/control"
grep -Fq 'Provides: touch-keyboard' "$root/debian/control"
grep -Fq 'Conflicts: touch-keyboard' "$root/debian/control"
grep -Fq 'Replaces: touch-keyboard' "$root/debian/control"
grep -Fq 'deccecb08889aa031664f5e22ec5c4c33fb6c41c' "$root/ATTRIBUTION.md"
grep -Fxq '3.0 (quilt)' "$root/debian/source/format"
grep -Fq 'extend-diff-ignore' "$root/debian/source/options"

if grep -R -n -E '/etc/touch_keyboard|touch-keyboard-handler\.service|/dev/touch_keyboard' \
		"$root" \
		--exclude-dir=.git \
		--exclude-dir=.debhelper \
		--exclude-dir='build*' \
		--exclude-dir='obj-*' \
		--exclude-dir=halo-keyboard \
		--exclude=README.md \
		--exclude='*.postinst' \
		--exclude=check-maintainer-scripts.sh \
		--exclude=check-project.sh; then
	echo 'legacy runtime name found outside documented migration code' >&2
	exit 1
fi

echo 'project metadata: PASS'
