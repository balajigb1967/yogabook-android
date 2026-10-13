#!/usr/bin/env bash
# One-command build of the Yoga Book Android 16 (LineageOS 23.2) ISO.
#
#   ./scripts/build-local.sh [--skip-sync] [--clean] [--jobs N]
#
# Requirements: Ubuntu 22.04/24.04 or WSL2, >=140 GB free disk, >=16 GB RAM.
# Produces: dist/YOGABOOK-x86_64-<version>-live.iso (+ .sha256)
set -euo pipefail

SRC="${SRC:-$HOME/lineage}"
OUTDISK="${OUTDISK:-}"   # optional: separate mount point for out/ (small-disk setups)
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT=lineage_YOGABOOK_x86_64
JOBS="$(nproc)"
DO_SYNC=1
CLEAN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-sync) DO_SYNC=0 ;;
    --clean) CLEAN=1 ;;
    --jobs) JOBS="$2"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { echo; echo "#### $* ####"; }

# ---------------------------------------------------------------- disk check
free_gb=$(df -BG --output=avail "$SRC" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
if [ "${free_gb:-0}" -lt 120 ]; then
  echo "WARNING: only ${free_gb}G free at $SRC - the build needs ~120 GB total." >&2
fi

# ---------------------------------------------------------------- sync
if [ "$DO_SYNC" = 1 ]; then
  say "Syncing LineageOS 23.2 (shallow) + Yoga Book manifest"
  mkdir -p "$SRC"
  cd "$SRC"
  if [ ! -d .repo ]; then
    repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 \
      --depth=1 --current-branch --no-clone-bundle -q
  fi
  mkdir -p .repo/local_manifests
  cp "$HERE/manifest/local_manifests/yogabook.xml" .repo/local_manifests/
  repo sync -c -j"$JOBS" --no-tags --no-clone-bundle --force-sync
fi

# ---------------------------------------------------------------- overlay
say "Overlaying this repository onto device/yogabook"
mkdir -p "$SRC/device/yogabook"
rsync -a --delete --exclude '.git' --exclude 'dist' --exclude 'out' \
  "$HERE/" "$SRC/device/yogabook/"

# ---------------------------------------------------------------- kernel patches
say "Applying Yoga Book kernel patches"
SRC="$SRC" bash "$HERE/scripts/apply-kernel-patches.sh"

# ---------------------------------------------------------------- build
say "Building $PRODUCT"
cd "$SRC"
[ "$CLEAN" = 1 ] && rm -rf out
if [ -n "$OUTDISK" ]; then
  mkdir -p "$OUTDISK/out"
  rm -rf out
  ln -sfn "$OUTDISK/out" out
  export TMPDIR="$OUTDISK/tmp"
  mkdir -p "$TMPDIR"
fi
set +e
# shellcheck disable=SC1091
source build/envsetup.sh >/dev/null
lunch "$PRODUCT-eng"
m -j"$JOBS" yogabook-liveiso
build_rc=$?
set -e
[ $build_rc -ne 0 ] && { echo "BUILD FAILED (see errors above)"; exit $build_rc; }

# ---------------------------------------------------------------- multi-kernel ISO
say "Packaging multi-kernel ISO (rEFInd)"
if [ -x "$HERE/scripts/make-multi-kernel-iso.sh" ]; then
  SRC="$SRC" bash "$HERE/scripts/make-multi-kernel-iso.sh"
fi

say "Done - ISO(s):"
ls -lh "$SRC/out/target/product/YOGABOOK_x86_64/"*.iso 2>/dev/null || true
mkdir -p "$HERE/dist"
cp -v "$SRC/out/target/product/YOGABOOK_x86_64/"*live*.iso* "$HERE/dist/" 2>/dev/null || true
cp -v "$SRC/dist/"*.iso "$HERE/dist/" 2>/dev/null || true
sha256sum "$HERE/dist"/*.iso > "$HERE/dist/SHA256SUMS" 2>/dev/null || true
cat "$HERE/dist/SHA256SUMS" 2>/dev/null || true
