#!/usr/bin/env bash
# build-kernel.sh — Build a Lenovo Yoga Book (YB1-X91F) kernel from
# jekhor/yogabook-linux-kernel and package it for injection into a
# Bliss/Bass 16.9.7 (Android-x86) ISO.
#
# Outputs (in $OUT_DIR):
#   bzImage-<krel>            bootable kernel (drop-in replacement for ISO /kernel)
#   modules-<krel>.tar.gz     full module tree + depmod db (initrd/lib/modules)
#   config-<krel>, System.map-<krel>, KREL
#
# Env:
#   KERNEL_REF   git ref of jekhor/yogabook-linux-kernel   (default: master)
#   KERNEL_SRC   existing kernel checkout to use instead of cloning
#   JOBS         parallel build jobs                       (default: nproc)
#   OUT_DIR      output directory                          (default: artifacts)
set -euo pipefail

KERNEL_REPO="https://github.com/jekhor/yogabook-linux-kernel"
KERNEL_REF="${KERNEL_REF:-master}"
JOBS="${JOBS:-$(nproc)}"
OUT_DIR="${OUT_DIR:-artifacts}"
FRAGMENT="$(cd "$(dirname "$0")" && pwd)/kernel/yogabook-android.fragment"

mkdir -p "$OUT_DIR"

if [[ -n "${KERNEL_SRC:-}" ]]; then
    LINUX="$KERNEL_SRC"
    echo ">>> Using existing kernel tree: $LINUX"
else
    LINUX="$PWD/linux"
    if [[ ! -d "$LINUX" ]]; then
        echo ">>> Shallow-cloning $KERNEL_REPO (ref $KERNEL_REF) ..."
        git clone --depth 1 --branch "$KERNEL_REF" "$KERNEL_REPO" "$LINUX"
    fi
fi
cd "$LINUX"

echo ">>> Configuring: yogabook_defconfig + Android fragment"
mkdir -p out
cp arch/x86/configs/yogabook_defconfig out/.config
./scripts/kconfig/merge_config.sh -m -O out out/.config "$FRAGMENT"
make O=out olddefconfig

echo ">>> Merged config sanity check"
for sym in CONFIG_ANDROID_BINDERFS CONFIG_INPUT_UINPUT CONFIG_HIDRAW \
           CONFIG_SND_SOC_RT5645 CONFIG_DRM_I915 CONFIG_TOUCHSCREEN_GOODIX; do
    grep -q "^$sym=y\|^$sym=m" out/.config && echo "    OK   $sym" \
        || echo "    MISS $sym  (not present in this kernel tree — check fragment)"
done

echo ">>> Building bzImage + modules (-j$JOBS)"
make O=out -j"$JOBS" bzImage modules

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
