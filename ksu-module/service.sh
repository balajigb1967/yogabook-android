#!/system/bin/sh
# Lenovo Yoga Book (YB1-X91F) Driver Service (KernelSU / Magisk late-start)

MODDIR=${0%/*}
LOG=/data/local/tmp/yogabook-service.log
exec > $LOG 2>&1
echo "=== Yoga Book Driver Service Started: $(date) ==="

# -------------------------------------------------------------
# 1. Bluetooth Initialization
# -------------------------------------------------------------
echo "--- Initializing Bluetooth ---"
rfkill unblock all 2>/dev/null || true
rfkill unblock bluetooth 2>/dev/null || true

# Test serial UART ports for Broadcom BCM4356
for tty in /dev/ttyS1 /dev/ttyS0 /dev/ttyS2; do
    if [ -c "$tty" ]; then
        echo "Attempting btattach on $tty..."
        btattach -B "$tty" -P bcm -S 3000000 2>&1 &
        sleep 2
        if hciconfig hci0 2>/dev/null | grep -q "hci0"; then
            echo "[YB] Bluetooth attached on $tty (hci0 up)"
            hciconfig hci0 up 2>/dev/null || true
            break
        fi
    fi
done

# -------------------------------------------------------------
# 2. Audio Initialization
# -------------------------------------------------------------
echo "--- Initializing Audio ---"
sleep 2

# Log sound cards
echo "Available sound cards:"
cat /proc/asound/cards 2>&1 || true

# Apply UCM profiles
echo "Applying UCM2 verbs..."
alsaucm -c cht-yogabook set _verb HiFi 2>&1 || \
alsaucm -c cht-rt5677 set _verb HiFi 2>&1 || \
alsaucm -c cht-bsw-rt5677 set _verb HiFi 2>&1 || true

# Unmute all common Intel Cherry Trail Realtek mixer controls
for card in 0 1 2; do
    amixer -c $card sset "Speaker" on 100% 2>/dev/null || true
    amixer -c $card sset "Headphone" on 100% 2>/dev/null || true
    amixer -c $card sset "DAC1" 100% 2>/dev/null || true
    amixer -c $card sset "Stereo DAC MIXL DAC L1" on 2>/dev/null || true
    amixer -c $card sset "Stereo DAC MIXR DAC R1" on 2>/dev/null || true
    amixer -c $card sset "HPOVOL" 100% 2>/dev/null || true
    amixer -c $card sset "SPKVOL" 100% 2>/dev/null || true
done

# -------------------------------------------------------------
# 3. Halo Keyboard Daemon
# -------------------------------------------------------------
echo "--- Initializing Halo Keyboard ---"

# Detect all input event devices
KB_DEV=""
for ev in /dev/input/event*; do
    name=$(cat "/sys/class/input/$(basename $ev)/device/name" 2>/dev/null)
    phys=$(cat "/sys/class/input/$(basename $ev)/device/phys" 2>/dev/null)
    echo "Found input: $ev -> Name='$name', Phys='$phys'"
    case "$name" in
        *"Goodix Capacitive TouchScreen"*)
            # The keyboard is usually the second touch device or on Yeti bus
            KB_DEV="$ev"
            ;;
    esac
done

if [ -n "$KB_DEV" ]; then
    ln -sf "$KB_DEV" /dev/touch_keyboard
    ln -sf "$KB_DEV" /dev/halo_keyboard
    echo "Linked $KB_DEV to /dev/touch_keyboard"

    DAEMON="$MODDIR/system/bin/halo-keyboard-handler"
    [ -x "$DAEMON" ] || DAEMON="/system/bin/halo-keyboard-handler"
    [ -x "$DAEMON" ] || DAEMON="/system/bin/touch_keyboard_handler"

    CONF="$MODDIR/system/etc/touch_keyboard"
    [ -d "$CONF" ] || CONF="/system/etc/touch_keyboard"

    if [ -x "$DAEMON" ] && [ -d "$CONF" ]; then
        cd "$CONF"
        echo "Starting $DAEMON in $CONF..."
        "$DAEMON" --config-directory "$CONF" > /data/local/tmp/halo-keyboard.log 2>&1 &
        echo "Daemon started (PID $!)."
    else
        echo "Daemon ($DAEMON) or config ($CONF) not found."
    fi
else
    echo "No Goodix touch surface detected for Halo Keyboard."
fi

echo "=== Yoga Book Driver Service Finished ==="
