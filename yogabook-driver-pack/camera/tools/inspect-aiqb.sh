#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

expected_name=OV2740_CJAE533_CHT.cpf
expected_size=33720
expected_sha256=b6a240c4e47ed1187987f9f68d8e68d392b758467914aa7bcc73993fe7952a55
structure_only=false

if [[ ${1:-} == --structure-only ]]; then
	structure_only=true
	shift
fi

if [[ $# -ne 1 || ! -f $1 ]]; then
	echo "usage: ${0##*/} [--structure-only] FILE" >&2
	exit 2
fi

input=$1
signature=$(od -An -N4 -tx1 "$input" | tr -d ' \n')
[[ $signature == 41495142 ]] || {
	echo "ERROR: $input does not have an AIQB signature" >&2
	exit 1
}

printable=$(strings -a "$input")
grep -Fq 'OV2740 V11 tuning' <<<"$printable" || {
	echo "ERROR: $input does not identify the expected OV2740 V11 tuning" >&2
	exit 1
}

size=$(stat -c %s "$input")
sha256=$(sha256sum "$input" | awk '{print $1}')

if ! $structure_only; then
	[[ $size -eq $expected_size ]] || {
		echo "ERROR: size $size does not match expected $expected_size" >&2
		exit 1
	}
	[[ $sha256 == "$expected_sha256" ]] || {
		echo "ERROR: SHA-256 does not match the inspected Lenovo artifact" >&2
		exit 1
	}
fi

printf 'AIQB_FILE: %s\n' "${input##*/}"
printf 'AIQB_EXPECTED_NAME: %s\n' "$expected_name"
printf 'AIQB_SIZE: %s\n' "$size"
printf 'AIQB_SHA256: %s\n' "$sha256"
if $structure_only; then
	echo 'AIQB_VALIDATION: STRUCTURE_ONLY'
else
	echo 'AIQB_VALIDATION: EXACT_MATCH'
fi
