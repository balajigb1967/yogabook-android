#!/usr/bin/env bash
# build-kernel.sh — Build the Yoga Book kernel for Android (Bass/Bliss 16.9.7).
#
# Source:   Yoga-Book/Yoga-Book-Linux-Kernel (submission/yogabook-x91l-v2, 7.2.0)
#           — the tree behind the Yoga-Book org's validated X91 hardware stack
#           (touchscreen, sound, halo keyboard, pen, Wi-Fi; LTE on X91L).
# Config:   the EXACT config from their published linux-image .deb (their
#           hardware validation baseline), merged with kernel/yogabook-android.fragment
#           (Android binder/binderfs, PSI, live-boot FSes, uinput).
#
# Outputs (in $OUT_DIR):
#   bzImage-<krel>, modules-<krel>.tar.gz, config-<krel>, System.map-<krel>, KREL
set -euo pipefail

KERNEL_REPO="https://github.com/Yoga-Book/Yoga-Book-Linux-Kernel"
KERNEL_REF="${KERNEL_REF:-submission/yogabook-x91l-v2}"
KERNEL_IMG_DEB="${KERNEL_IMG_DEB:-https://github.com/Yoga-Book/Yoga-Book-Linux-Kernel/releases/download/v7.2.0-yogabook-20260901-232318/linux-image-7.2.0-yogabook-20260901-232318_7.2.0-14793-g42ad949c9ebb-5_amd64.deb}"
JOBS="${JOBS:-$(nproc)}"
OUT_DIR="${OUT_DIR:-artifacts}"
WORKROOT="$PWD"
FRAGMENT="$(cd "$(dirname "$0")" && pwd)/kernel/yogabook-android.fragment"

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"   # absolute: we cd into linux/ below

# ccache: objects persist between CI runs (via the ~/.ccache cache), so an
# unchanged kernel rebuilds in minutes instead of an hour
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-3G}"
export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
export CCACHE_COMPILERCHECK=content
CC="gcc"
if command -v ccache >/dev/null 2>&1; then
    CC="ccache gcc"
fi

if [[ -n "${KERNEL_SRC:-}" ]]; then
    LINUX="$KERNEL_SRC"
    echo ">>> Using existing kernel tree: $LINUX"
else
    LINUX="$WORKROOT/linux"
fi

# CI cache hygiene: a restored linux/ may be partial or from another ref
if [[ -d "$LINUX" && ! -f "$LINUX/Makefile" ]]; then
    echo ">>> Partial kernel tree from cache — resetting"
    rm -rf "$LINUX"
fi
if [[ -d "$LINUX" && "$(cat "$LINUX/.yb-ref" 2>/dev/null)" != "$KERNEL_REF" ]]; then
    echo ">>> Kernel ref changed — recloning"
    rm -rf "$LINUX"
fi

if [[ ! -d "$LINUX" ]]; then
    echo ">>> Cloning $KERNEL_REPO (ref $KERNEL_REF) ..."
    git clone --depth 1 --branch "$KERNEL_REF" "$KERNEL_REPO" "$LINUX"
fi

echo ">>> Extracting tested config from Yoga-Book linux-image .deb"
CFG_DEB="$WORKROOT/kernel-image.deb"
curl -fL --retry 3 -o "$CFG_DEB" "$KERNEL_IMG_DEB"
mkdir -p "$WORKROOT/debx"
dpkg-deb -x "$CFG_DEB" "$WORKROOT/debx"
BASE_CFG="$(find "$WORKROOT/debx/boot" -name 'config-*' | head -n1)"
[[ -n "$BASE_CFG" ]] || { echo "ERROR: no config-* inside the .deb" >&2; exit 1; }
echo "    using $(basename "$BASE_CFG")"

cd "$LINUX"
echo "$KERNEL_REF" > "$LINUX/.yb-ref"
echo ">>> Configuring: Yoga-Book validated config + Android fragment"
mkdir -p out
cp "$BASE_CFG" out/.config
./scripts/kconfig/merge_config.sh -m -O out out/.config "$FRAGMENT"
make O=out olddefconfig

echo ">>> Merged config sanity check"
for sym in CONFIG_ANDROID_BINDERFS CONFIG_INPUT_UINPUT CONFIG_HIDRAW \
           CONFIG_DRM_I915 CONFIG_PSI CONFIG_DRM_SIMPLEDRM; do
    grep -q "^$sym=y\|^$sym=m" out/.config && echo "    OK   $sym" \
        || echo "    MISS $sym"
done

echo ">>> Building bzImage + modules (-j$JOBS)"
make O=out CC="$CC" -j"$JOBS" bzImage modules

KREL="$(make -s O=out kernelrelease)"
echo ">>> Kernel release: $KREL"

echo ">>> Installing modules"
rm -rf modout
make O=out INSTALL_MOD_PATH="$PWD/modout" INSTALL_MOD_STRIP=1 modules_install
mkdir -p modout/boot
cp out/System.map "modout/boot/System.map-$KREL"
depmod -b modout "$KREL"

echo ">>> Packaging artifacts"
cp out/arch/x86/boot/bzImage      "$OUT_DIR/bzImage-$KREL"
cp out/.config                    "$OUT_DIR/config-$KREL"
cp out/System.map                 "$OUT_DIR/System.map-$KREL"
tar czf "$OUT_DIR/modules-$KREL.tar.gz" -C modout lib
echo "$KREL" > "$OUT_DIR/KREL"

if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "KREL=$KREL" >> "$GITHUB_ENV"
fi

echo ">>> Done:"
ls -lh "$OUT_DIR"
