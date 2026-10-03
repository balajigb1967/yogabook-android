#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause

set -Eeuo pipefail

root=${1:?project root is required}
temporary_base=${TMPDIR:-/var/tmp}
temporary_root=$(mktemp -d "$temporary_base/halo-keyboard-backlight.XXXXXX")
trap 'rm -rf -- "$temporary_root"' EXIT

policy=$root/libexec/ensure-backlight-minimum
test -x "$policy"

printf '100\n' >"$temporary_root/max_brightness"
printf '0\n' >"$temporary_root/brightness"
"$policy" "$temporary_root"
test "$(cat "$temporary_root/brightness")" = 20

printf '19\n' >"$temporary_root/brightness"
"$policy" "$temporary_root"
test "$(cat "$temporary_root/brightness")" = 20

printf '75\n' >"$temporary_root/brightness"
"$policy" "$temporary_root"
test "$(cat "$temporary_root/brightness")" = 75

printf '7\n' >"$temporary_root/max_brightness"
printf '0\n' >"$temporary_root/brightness"
"$policy" "$temporary_root"
test "$(cat "$temporary_root/brightness")" = 2

printf 'invalid\n' >"$temporary_root/max_brightness"
if "$policy" "$temporary_root" 2>/dev/null; then
	echo 'invalid maximum brightness unexpectedly accepted' >&2
	exit 1
fi

echo 'backlight policy: PASS'
