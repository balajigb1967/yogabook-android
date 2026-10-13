#!/vendor/bin/sh
# Yoga Book Halo keyboard launcher.
#
# The Halo keyboard is a Goodix capacitive surface ("Goodix Capacitive
# TouchScreen" on DMI LenovoYB1-X9*) used as a touch keyboard/touchpad.
# Linux udev matches that via hwdb; Android ueventd cannot, so this
# script finds the event node from /proc/bus/input/devices, creates the
# symlink the handler expects (/dev/touch_keyboard), sets up the DRV2604
# haptic symlinks and execs the handler.

CFG=/vendor/etc/touch_keyboard
WORK=/data/vendor/touch_keyboard

log -t halo_keyboard "starting"

mkdir -p "$WORK" || exit 1
cd "$WORK" || exit 1

cp -f "$CFG/touch-hw.csv" . 2>/dev/null
cp -f "$CFG/layout.csv" layout.csv 2>/dev/null
cp -f "$CFG/layout-touchpad.csv" . 2>/dev/null

# Wait (up to ~30s) for the Goodix keyboard surface to enumerate.
ev=""
i=0
while [ "$i" -lt 60 ]; do
    ev=$(sed -n '/Goodix Capacitive TouchScreen/,/^$/p' /proc/bus/input/devices \
         | sed -n 's/.*Handlers=\(.*\)/\1/p' | tr ' ' '\n' | grep '^event' | head -1)
    [ -n "$ev" ] && break
    sleep 0.5
    i=$((i + 1))
done

if [ -z "$ev" ]; then
    log -t halo_keyboard "Goodix keyboard surface not found; not starting"
    exit 1
fi

ln -sf "/dev/input/$ev" /dev/touch_keyboard
log -t halo_keyboard "keyboard surface -> /dev/input/$ev"

# DRV2604 haptic feedback devices (optional).
for spec in "i2c-DRV2604:00 right_vibrator" "i2c-DRV2604:01 left_vibrator" \
            "i2c-drv2604l.0 right_vibrator" "i2c-drv2604l.1 left_vibrator"; do
    name=${spec% *}
    link=${spec#* }
    hv=$(awk -v name="$name" '
        BEGIN { RS="" }
        index($0, "Name=" name) {
            match($0, /Handlers=([a-z0-9 ]+)/, a)
            split(a[1], h, " ")
            for (i in h) if (h[i] ~ /^event/) print h[i]
        }' /proc/bus/input/devices | head -1)
    [ -n "$hv" ] && ln -sf "/dev/input/$hv" "/dev/$link"
done

exec /vendor/bin/touch_keyboard_handler "$@"
