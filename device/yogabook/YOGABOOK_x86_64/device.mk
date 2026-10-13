#
# SPDX-License-Identifier: Apache-2.0
#

TARGET_DEVICE_PATH := device/yogabook/YOGABOOK_x86_64

# ---- Halo keyboard (Goodix surface -> uinput) ------------------------------
PRODUCT_PACKAGES += \
    touch_keyboard_handler \
    halo-keyboard-start.sh \
    touch_keyboard_hw.csv \
    touch_keyboard_layout_pc104.csv \
    touch_keyboard_layout_pc105.csv \
    touch_keyboard_layout_touchpad.csv

PRODUCT_COPY_FILES += \
    device/yogabook/halo-keyboard/touch_keyboard.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/touch_keyboard.rc

# ---- Boot & hardware failure log capture -----------------------------------
PRODUCT_PACKAGES += \
    yablog.sh

PRODUCT_COPY_FILES += \
    device/yogabook/diagnostics/yogabook-logcapture.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/yogabook-logcapture.rc

# ---- ueventd additions (uinput, input devices, haptics) --------------------
PRODUCT_COPY_FILES += \
    device/yogabook/YOGABOOK_x86_64/configs/ueventd.yogabook.rc:$(TARGET_COPY_OUT_VENDOR)/etc/ueventd.yogabook.rc
