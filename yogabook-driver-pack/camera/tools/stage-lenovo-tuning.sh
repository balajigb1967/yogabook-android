#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -lt 1 || $# -gt 2 || ! -f $1 ]]; then
	echo "usage: ${0##*/} SOURCE [PRIVATE_DIRECTORY]" >&2
	exit 2
fi

source_file=$1
destination_directory=${2:-$root/artifacts/private}
destination=$destination_directory/OV2740_CJAE533_CHT.cpf

"$root/tools/inspect-aiqb.sh" "$source_file"
install -d -m 0700 "$destination_directory"
install -m 0600 "$source_file" "$destination"
(
	cd "$destination_directory"
	sha256sum "${destination##*/}" >"${destination##*/}.sha256"
)

printf 'Staged private tuning: %s\n' "$destination"
printf 'No runtime consumer was installed or activated.\n'
