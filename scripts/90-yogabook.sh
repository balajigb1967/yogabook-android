# 90-yogabook.sh — Sourced by Android-x86 initrd /init during boot
# Sets up Yoga Book firmware, ALSA UCM, and hooks Android's init.sh

echo "[YB] Applying Yoga Book hardware bindings..."

YB_DIR=""
if [ -d "/src/yogabook" ]; then
    YB_DIR="/src/yogabook"
elif [ -d "/mnt/$SRC/yogabook" ]; then
    YB_DIR="/mnt/$SRC/yogabook"
elif [ -d "/iso/yogabook" ]; then
    YB_DIR="/iso/yogabook"
fi

if [ -n "$YB_DIR" ]; then
    echo "[YB] Using driver bundle from $YB_DIR"

    # 1. Bind-mount SOF & Broadcom Firmware into vendor firmware directories
    if [ -f "$YB_DIR/firmware/intel/sof-tplg/sof-cht-rt5677.tplg" ]; then
        mkdir -p /android/system/vendor/firmware/intel/sof-tplg
        mkdir -p /android/system/etc/firmware/intel/sof-tplg 2>/dev/null || true
        mount --bind "$YB_DIR/firmware/intel/sof-tplg/sof-cht-rt5677.tplg" \
                     /android/system/vendor/firmware/intel/sof-tplg/sof-cht-rt5677.tplg 2>/dev/null || true
        mount --bind "$YB_DIR/firmware/intel/sof-tplg/sof-cht-rt5677.tplg" \
                     /android/system/etc/firmware/intel/sof-tplg/sof-cht-rt5677.tplg 2>/dev/null || true
        echo "[YB] Bound sof-cht-rt5677.tplg"
    fi

    if [ -f "$YB_DIR/firmware/brcm/BCM4356A2.hcd" ]; then
        mkdir -p /android/system/vendor/firmware/brcm
        mkdir -p /android/system/etc/firmware/brcm 2>/dev/null || true
        mount --bind "$YB_DIR/firmware/brcm/BCM4356A2.hcd" \
                     /android/system/vendor/firmware/brcm/BCM4356A2.hcd 2>/dev/null || true
        mount --bind "$YB_DIR/firmware/brcm/BCM4356A2.hcd" \
                     /android/system/etc/firmware/brcm/BCM4356A2.hcd 2>/dev/null || true
        echo "[YB] Bound BCM4356A2.hcd"
    fi

    # 2. Bind-mount ALSA UCM2 configurations
    if [ -d "$YB_DIR/ucm2" ]; then
        mkdir -p /android/system/usr/share/alsa/ucm2
        mount --bind "$YB_DIR/ucm2" /android/system/usr/share/alsa/ucm2 2>/dev/null || true
        echo "[YB] Bound ALSA UCM2 profiles"
    fi

    # 3. Hook Android userspace /system/etc/init.sh
    if [ -f /android/system/etc/init.sh ]; then
        if ! grep -q 'init-yogabook.sh' /android/system/etc/init.sh 2>/dev/null; then
            cp /android/system/etc/init.sh /tmp/init.sh
            cat <<'HOOK' >> /tmp/init.sh

# ---- Lenovo Yoga Book Hardware Startup ----
if [ -x /src/yogabook/init-yogabook.sh ]; then
    sh /src/yogabook/init-yogabook.sh &
elif [ -x /and-yb/yogabook/init-yogabook.sh ]; then
    sh /and-yb/yogabook/init-yogabook.sh &
fi
HOOK
            chmod 755 /tmp/init.sh
            mount --bind /tmp/init.sh /android/system/etc/init.sh
            echo "[YB] Hooked Android /system/etc/init.sh for hardware init"
        fi
    fi
else
    echo "[YB] Warning: yogabook assets directory not found"
fi
