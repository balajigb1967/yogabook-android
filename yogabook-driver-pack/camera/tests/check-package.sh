#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

package=${1:?usage: check-package.sh PACKAGE.deb}
[[ -f $package ]] || {
	echo "ERROR: package not found: $package" >&2
	exit 1
}

temporary_root=${TMPDIR:-/tmp}
temporary_directory=$(mktemp -d "$temporary_root/yogabook-camera-package.XXXXXX")
cleanup() {
	rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

dpkg-deb --extract "$package" "$temporary_directory/root"
dpkg-deb --control "$package" "$temporary_directory/control"

[[ $(dpkg-deb --field "$package" Package) == yogabook-camera ]]
[[ $(dpkg-deb --field "$package" Architecture) == all ]]

required_payload=(
	etc/modprobe.d/yogabook-camera.conf
	etc/modules-load.d/yogabook-camera.conf
	etc/yogabook-camera/cameras.json
	usr/bin/yogabook_camera_control.py
	usr/lib/systemd/system/yogabook-camera-prepare.service
	usr/lib/systemd/system/yogabook-camera-sleep.service
	usr/lib/systemd/system/yogabook-camera.service
	usr/lib/udev/rules.d/72-yogabook-camera-private.rules
	usr/libexec/yogabook-camera/camera-sleep.sh
	usr/libexec/yogabook-camera/prepare-camera.sh
	usr/libexec/yogabook-camera/yogabook_camera.py
	usr/libexec/yogabook-camera/yogabook_camera_capture.py
)
for payload in "${required_payload[@]}"; do
	test -f "$temporary_directory/root/$payload"
done

for document in ACCEPTANCE ARCHITECTURE CALIBRATION KERNEL-CONTRACT STATUS; do
	path=$temporary_directory/root/usr/share/doc/yogabook-camera/$document.md
	test -f "$path" || test -f "$path.gz"
done

for executable in \
	usr/bin/yogabook_camera_control.py \
	usr/libexec/yogabook-camera/camera-sleep.sh \
	usr/libexec/yogabook-camera/prepare-camera.sh \
	usr/libexec/yogabook-camera/yogabook_camera.py \
	usr/libexec/yogabook-camera/yogabook_camera_capture.py; do
	test -x "$temporary_directory/root/$executable"
done

grep -Fqx '/etc/yogabook-camera/cameras.json' \
	"$temporary_directory/control/conffiles"
grep -Fqx '/etc/modprobe.d/yogabook-camera.conf' \
	"$temporary_directory/control/conffiles"
grep -Fqx '/etc/modules-load.d/yogabook-camera.conf' \
	"$temporary_directory/control/conffiles"

python3 "$(dirname "${BASH_SOURCE[0]}")/check-camera-config.py" \
	"$temporary_directory/root/etc/yogabook-camera/cameras.json"
bash -n \
	"$temporary_directory/root/usr/libexec/yogabook-camera/prepare-camera.sh" \
	"$temporary_directory/root/usr/libexec/yogabook-camera/camera-sleep.sh" \
	"$temporary_directory/control/postinst" \
	"$temporary_directory/control/preinst" \
	"$temporary_directory/control/prerm" \
	"$temporary_directory/control/postrm"

echo "Yoga Book Camera package: PASS ($package)"
