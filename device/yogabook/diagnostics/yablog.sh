#!/vendor/bin/sh
# yablog.sh - Yoga Book boot & hardware failure log capture.
#
# Subcommands:
#   boot      main service entry: snapshot + early-log import + live watchers
#   snapshot  one-shot hardware/driver state report
#
# Logs go to every writable candidate, so a failed boot can always be
# diagnosed by pulling the SD card into a PC (bootlogs/ on the card)
# or via MTP (bootlogs/ in internal storage).

TAG=yablog

log_it() { log -t "$TAG" "$@"; }

# ---- locate log directories -------------------------------------------------
CANDIDATES="/data/media/0/bootlogs /sdcard/bootlogs"

# Also try the boot media that holds the android dir (writable FAT/exFAT).
find_media_logs() {
    # The generic_init mount handler bind-mounts the android dir; look for a
    # mounted vfat/exfat/f2fs/ext4 partition that contains the android dir marker.
    for m in $(awk '$3 ~ /^(vfat|exfat|ext4|f2fs|fuseblk)$/ {print $2}' /proc/mounts); do
        if [ -e "$m/ANDRID" ] || [ -e "$m/ANDROID" ] || [ -d "$m/android" ]; then
            echo "$m/bootlogs"
            return
        fi
    done
}

MEDIA_LOGS=$(find_media_logs)
[ -n "$MEDIA_LOGS" ] && CANDIDATES="$MEDIA_LOGS $CANDIDATES"

LOGDIRS=""
for d in $CANDIDATES; do
    if mkdir -p "$d" 2>/dev/null && touch "$d/.w" 2>/dev/null; then
        rm -f "$d/.w"
        LOGDIRS="$LOGDIRS $d"
    fi
done

[ -z "$LOGDIRS" ] && { log_it "no writable log directory found"; exit 1; }

log_it "logging to:$LOGDIRS"

# ---- snapshot ---------------------------------------------------------------
snapshot() {
    ts=$(date +%Y%m%d-%H%M%S)
    for d in $LOGDIRS; do
        f="$d/hwreport-$ts.txt"
        {
            echo "=== Yoga Book hardware report $ts ==="
            echo; echo "--- /proc/cmdline ---"; cat /proc/cmdline
            echo; echo "--- getprop ---"; getprop
            echo; echo "--- dmesg ---"; dmesg
            echo; echo "--- /proc/modules (not loaded first) ---"
            cat /proc/modules
            echo; echo "--- failed module requests (dmesg grep) ---"
            dmesg | grep -iE 'firmware|error|fail|timeout|probe' | tail -200
            echo; echo "--- /proc/bus/input/devices ---"; cat /proc/bus/input/devices
            echo; echo "--- /sys/class/drm ---"
            for c in /sys/class/drm/*/; do
                echo "$c: $(cat "$c/status" 2>/dev/null)"
            done
            echo; echo "--- PCI devices ---"
            for p in /sys/bus/pci/devices/*/; do
                echo "$(basename "$p") $(cat "$p/vendor" 2>/dev/null):$(cat "$p/device" 2>/dev/null) driver=$(basename "$(readlink "$p/driver" 2>/dev/null)")"
            done
            echo; echo "--- USB devices (toybox lsusb) ---"; lsusb 2>/dev/null
            echo; echo "--- USB device descriptors ---"
            for u in /sys/bus/usb/devices/*; do
                [ -f "$u/idVendor" ] || continue
                echo "$(basename "$u") $(cat "$u/idVendor"):$(cat "$u/idProduct") $(cat "$u/product" 2>/dev/null) driver=$(basename "$(readlink "$u/driver" 2>/dev/null)")"
            done
            echo; echo "--- MMC / block devices ---"; ls -l /dev/block 2>/dev/null
            echo; echo "--- /proc/partitions ---"; cat /proc/partitions
            echo; echo "--- mounts ---"; cat /proc/mounts
            echo; echo "--- power supply ---"
            for ps in /sys/class/power_supply/*; do
                echo "$(basename "$ps"): type=$(cat "$ps/type" 2>/dev/null) status=$(cat "$ps/status" 2>/dev/null) capacity=$(cat "$ps/capacity" 2>/dev/null)"
            done
            echo; echo "--- DMI ---"
            cat /sys/class/dmi/id/product_name /sys/class/dmi/id/product_version /sys/class/dmi/id/bios_version 2>/dev/null
            echo; echo "--- logcat (crash+main, boot) ---"
            logcat -d -b crash 2>/dev/null | tail -300
        } > "$f" 2>&1
        log_it "wrote $f"
    done
}

# ---- early boot logs written by generic_init to /metadata -------------------
import_early() {
    for d in $LOGDIRS; do
        cp -a /metadata/*early* "$d/" 2>/dev/null
        cp -a /metadata/log* "$d/" 2>/dev/null
    done
}

# ---- live watchers ----------------------------------------------------------
MAX=8388608   # 8 MiB per file
rotate() {
    f="$1"
    [ -f "$f" ] || return
    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    [ "$sz" -gt "$MAX" ] && mv -f "$f" "$f.1"
}

watch_dmesg() {
    d=$(echo "$LOGDIRS" | awk '{print $1}')
    while true; do
        f="$d/dmesg.log"
        dmesg -w >> "$f" 2>/dev/null
        sleep 1
        rotate "$f"
    done
}

watch_logcat() {
    d=$(echo "$LOGDIRS" | awk '{print $1}')
    while true; do
        f="$d/logcat.log"
        logcat -v threadtime -b main,system,crash >> "$f" 2>/dev/null
        sleep 1
        rotate "$f"
    done
}

case "$1" in
    boot)
        import_early
        snapshot
        # keep persistent copies of the report on every candidate dir
        watch_dmesg &
        watch_logcat &
        # refresh the hardware report every 10 minutes while failures persist
        while true; do sleep 600; snapshot; done
        ;;
    snapshot)
        snapshot
        ;;
    *)
        echo "usage: yablog.sh {boot|snapshot}"
        exit 1
        ;;
esac
