#!/bin/sh
# Lenovo Yoga Book (YB1-X91F) Hardware Initialization Script
# Runs at Android boot via /system/etc/init.sh hook

LOG=/data/yogabook-init.log
exec > $LOG 2>&1
echo "[YB] Starting Yoga Book hardware initialization: $(date)"

# -------------------------------------------------------------
# 1. Unblock Bluetooth & RFKill
# -------------------------------------------------------------
echo "[YB] Unblocking RF devices..."
rfkill unblock all 2>/dev/null || true
rfkill unblock bluetooth 2>/dev/null || true

# Attach Broadcom Bluetooth UART if needed
if [ -e /dev/ttyS1 ] && ! hciconfig hci0 2>/dev/null | grep -q UP; then
    echo "[YB] Attaching Broadcom Bluetooth on /dev/ttyS1..."
    (
        sleep 3
        hciattach -s 115200 /dev/ttyS1 bcm43xx 3000000 flow 2>/dev/null || \
        btattach -B /dev/ttyS1 -P bcm -S 3000000 2>/dev/null || true
    ) &
fi

# -------------------------------------------------------------
# 2. Audio - Initialize ALSA UCM / RT5677
# -------------------------------------------------------------
echo "[YB] Configuring ALSA audio..."
alsaucm -c cht-yogabook set _verb HiFi 2>/dev/null || alsaucm -c cht-rt5677 set _verb HiFi 2>/dev/null || true

# Unmute and set speaker/headphone volumes
for card in 0 1 2; do
    amixer -c $card sset "Speaker" on 2>/dev/null || true
    amixer -c $card sset "Speaker" 100% 2>/dev/null || true
    amixer -c $card sset "Headphone" on 2>/dev/null || true
    amixer -c $card sset "Headphone" 100% 2>/dev/null || true
    amixer -c $card sset "DAC1" 100% 2>/dev/null || true
    amixer -c $card sset "Stereo DAC MIXL DAC L1" on 2>/dev/null || true
    amixer -c $card sset "Stereo DAC MIXR DAC R1" on 2>/dev/null || true
done

# -------------------------------------------------------------
# 3. Auto-Rotate / Sensors
# -------------------------------------------------------------
echo "[YB] Configuring accelerometer & rotation..."
setprop ro.hardware.sensors iio

# Probe IIO devices for the screen accelerometer
for d in /sys/bus/iio/devices/iio:device*; do
    if [ -f "$d/name" ]; then
        sname=$(cat "$d/name" 2>/dev/null)
        echo "[YB] Detected IIO sensor: $d -> $sname"
        case "$sname" in
            *accel*|*bma*|*BMC*|*HID*200073*)
                idx=$(basename "$d" | sed 's/iio:device//')
                setprop ro.iio.accel.order "$idx"
                setprop ro.iio.accel.x.opt 1
                setprop ro.iio.accel.y.opt 1
                setprop ro.iio.accel.z.opt 1
                break
                ;;
        esac
    fi
done

# -------------------------------------------------------------
# 4. Halo Keyboard
# -------------------------------------------------------------
echo "[YB] Configuring Halo Keyboard..."

# Find the Halo Keyboard Goodix touch device
KB_DEV=""
for ev in /dev/input/event*; do
    name=$(cat "/sys/class/input/$(basename $ev)/device/name" 2>/dev/null)
    phys=$(cat "/sys/class/input/$(basename $ev)/device/phys" 2>/dev/null)
    case "$name" in
        *"Goodix Capacitive TouchScreen"*)
            echo "[YB] Found Goodix touch input: $ev ($phys)"
            KB_DEV="$ev"
            ;;
    esac
done

if [ -n "$KB_DEV" ]; then
    ln -sf "$KB_DEV" /dev/halo_keyboard
    ln -sf "$KB_DEV" /dev/touch_keyboard
    echo "[YB] Linked $KB_DEV to /dev/halo_keyboard"

    # Search for the static daemon binary
    KB_BIN=""
    for b in /src/yogabook/halo-keyboard-handler \
             /and-yb/yogabook/halo-keyboard-handler \
             /system/bin/halo-keyboard-handler \
             /sbin/halo-keyboard-handler; do
        if [ -x "$b" ]; then
            KB_BIN="$b"
            break
        fi
    done

    # Search for config directory
    KB_CONF=""
    for c in /src/yogabook/config \
             /and-yb/yogabook/config \
             /etc/touch_keyboard \
             /etc/halo-keyboard; do
        if [ -d "$c" ]; then
            KB_CONF="$c"
            break
        fi
    done

    if [ -n "$KB_BIN" ] && [ -n "$KB_CONF" ]; then
        echo "[YB] Launching $KB_BIN with config $KB_CONF..."
        "$KB_BIN" --config-directory "$KB_CONF" >/data/halo-keyboard.log 2>&1 &
        echo "[YB] Halo keyboard daemon started (PID $!)."
    else
        echo "[YB] Warning: daemon binary ($KB_BIN) or config ($KB_CONF) missing."
    fi
else
    echo "[YB] Goodix touch surface not found."
fi

echo "[YB] Yoga Book hardware initialization finished."
