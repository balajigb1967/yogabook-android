#!/usr/bin/env bash
# Apply Yoga Book hardware backport patches to Kernel 6.18 (e.g. android-generic/kernel-zenith).
#
# Patches:
#   1. ASoC: Intel: Add Cherry Trail RT5677 machine driver (sound/soc/intel/boards/cht_rt5677.c)
#   2. ASoC: Intel: cht: Add Yoga Book RT5677 machine entry (sound/soc/intel/common/soc-acpi-intel-cht-match.c)
#   3. platform/x86: x86-android-tablets: Describe Yoga Book haptics (DRV2604)
#   4. platform/x86: x86-android-tablets: Add Yoga Book TS3A227E (headset jack detection)
#   5. platform/x86: x86-android-tablets: Add Yoga Book audio GPIOs (RT5677 GPIO2 & GPIO4)
#   6. Input: drv260x: Fix suspend and resume sequencing (haptics)
#   7. power: supply: core: Honor supplied-from with CONFIG_OF=y (fast charging fix)
#   8. xhci: Restore SSIC state on the Lenovo Yoga Book (XMM7260 USB SSIC)
#   9. platform/x86: Add Cherry Trail XMM7260 power driver (LTE modem)
#  10. media: atomisp: allow raw Bayer capture (OV2740 / OV8858 camera)
#  11. media: i2c: Add WV517S lens actuator driver
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
KSRC="${1:-${KSRC:-$HOME/kernel-zenith}}"
PATCH_DIR="$HERE/patches-kernel-6.18"

[ -d "$KSRC" ] || { echo "ERROR: kernel tree missing: $KSRC" >&2; exit 1; }
[ -d "$PATCH_DIR" ] || { echo "ERROR: patch dir missing: $PATCH_DIR" >&2; exit 1; }

echo "== Applying Yoga Book 6.18 Backport Patches to $KSRC =="

applied=0
failed=0

for p in "$PATCH_DIR"/*.patch; do
  [ -f "$p" ] || continue
  pname="$(basename "$p")"
  echo -n "  Applying $pname... "

  if git -C "$KSRC" am --3way --whitespace=nowarn "$p" 2>/dev/null; then
    echo "OK (git am)"
    applied=$((applied + 1))
  else
    git -C "$KSRC" am --abort 2>/dev/null || true
    if git -C "$KSRC" apply --whitespace=nowarn --reject "$p" 2>/dev/null; then
      echo "OK (git apply with rejects if any)"
      applied=$((applied + 1))
    else
      echo "FAILED"
      failed=$((failed + 1))
    fi
  fi
done

echo "== Done: $applied applied, $failed failed =="
[ "$failed" -eq 0 ] || exit 1
