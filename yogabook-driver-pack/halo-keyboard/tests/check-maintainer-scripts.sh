#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause

set -Eeuo pipefail

project_root=${1:?project root is required}
test_root=$(mktemp -d /tmp/halo-keyboard-maintscript.XXXXXX)

cleanup() {
	rm -rf -- "$test_root"
}
trap cleanup EXIT

install -D -m 0644 "$project_root/udev/61-halo-keyboard.hwdb" \
	"$test_root/usr/lib/udev/hwdb.d/61-halo-keyboard.hwdb"
install -D -m 0644 "$project_root/config/layouts/YB1-X9x-pc105.csv" \
	"$test_root/etc/halo-keyboard/layouts/YB1-X9x-pc105.csv"

mkdir -p "$test_root/etc/touch_keyboard"
printf '%s\n' 'custom migrated layout' >"$test_root/etc/touch_keyboard/layout.csv"
DPKG_ROOT=$test_root "$project_root/debian/halo-keyboard.postinst" configure
cmp -s "$test_root/etc/touch_keyboard/layout.csv" \
	"$test_root/etc/halo-keyboard/layout.csv"

rm -f -- "$test_root/etc/halo-keyboard/layout.csv" \
	"$test_root/etc/touch_keyboard/layout.csv"
DPKG_ROOT=$test_root "$project_root/debian/halo-keyboard.postinst" configure
[[ -L $test_root/etc/halo-keyboard/layout.csv ]]
[[ $(readlink "$test_root/etc/halo-keyboard/layout.csv") == \
	'layouts/YB1-X9x-pc105.csv' ]]

DPKG_ROOT=$test_root "$project_root/debian/halo-keyboard.postrm" remove

echo 'maintainer scripts: PASS'
