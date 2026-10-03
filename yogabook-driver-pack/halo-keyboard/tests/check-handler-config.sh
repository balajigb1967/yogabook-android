#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause

set -Eeuo pipefail

handler=${1:?handler path is required}
missing_directory=/definitely-not-present/halo-keyboard-test

set +e
output=$(cd / && "$handler" --config-directory "$missing_directory" 2>&1)
status=$?
set -e

if (( status != 1 )); then
	echo "handler unexpectedly exited with status $status" >&2
	exit 1
fi

grep -Fq "$missing_directory/hardware.csv" <<<"$output"

echo 'handler configuration path: PASS'
