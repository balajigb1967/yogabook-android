#!/usr/bin/env bash
# fetch-base-iso.sh — download the base Bliss/Bass 16.9.7 x86_64 ISO.
#
# Usage:  BASE_ISO_URL=<url> fetch-base-iso.sh <output-file>
#         fetch-base-iso.sh <output-file> [variant]   # variant: vanilla|foss|gapps
#
# If BASE_ISO_URL is unset, the SourceForge RSS listing for BlissOS16 is
# scanned for 16.9.7 ISOs and the first match for the preferred variant
# (default: vanilla, so the final ISO stays under GitHub's 2 GiB release
# asset limit) is downloaded.
set -euo pipefail

OUT="${1:?usage: fetch-base-iso.sh <output-file> [variant]}"
VARIANT="${2:-${BASE_ISO_VARIANT:-foss}}"

if [[ -n "${BASE_ISO_URL:-}" ]]; then
    URL="$BASE_ISO_URL"
else
    echo ">>> Resolving BlissOS 16.9.7 ($VARIANT) from SourceForge RSS ..."
    RSS="https://sourceforge.net/projects/blissos-x86/rss?path=/Official/BlissOS16"
    XML="$(curl -fsSL --retry 3 "$RSS")"
    URL="$(echo "$XML" \
        | grep -oE '<link>[^<]+\.iso/download</link>' \
        | sed -E 's#</?link>##g' \
        | grep '16\.9\.7' \
        | grep -i "$VARIANT" \
        | head -n1 || true)"
    if [[ -z "$URL" ]]; then
        # Fall back to any 16.9.7 ISO in the listing
        URL="$(echo "$XML" \
            | grep -oE '<link>[^<]+\.iso/download</link>' \
            | sed -E 's#</?link>##g' \
            | grep '16\.9\.7' \
            | head -n1 || true)"
    fi
    [[ -n "$URL" ]] || { echo "ERROR: no BlissOS 16.9.7 ISO found in RSS listing" >&2; exit 1; }
fi

echo ">>> Downloading: $URL"
curl -fL --retry 3 --retry-delay 5 -o "$OUT" "$URL"
echo ">>> Downloaded:"
ls -lh "$OUT"
