# Yoga Book YB1-91F Vendor Makefile
# Inherit from the proprietary vendor blob setup

# Vendor blobs for Yoga Book YB1-91F
# These would normally be extracted from the device or provided by vendor

# Audio firmware and configs
PRODUCT_COPY_FILES += \
    vendor/lenovo/yogabook/proprietary/firmware/RT5677/rt5677_dsp.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/rt5677_dsp.bin \
    vendor/lenovo/yogabook/proprietary/ucm/RT5677:$(TARGET_COPY_OUT_VENDOR)/share/alsa/ucm/RT5677

# Camera firmware
PRODUCT_COPY_FILES += \
    vendor/lenovo/yogabook/proprietary/firmware/camera/mbm_firmware.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/mbm_firmware.bin

# WiFi firmware
PRODUCT_COPY_FILES += \
    vendor/lenovo/yogabook/proprietary/firmware/wifi/rtl8723bs_fw.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/rtl8723bs_fw.bin

# Bluetooth firmware
PRODUCT_COPY_FILES += \
    vendor/lenovo/yogabook/proprietary/firmware/bluetooth/rtl8723bs_bt.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/rtl8723bs_bt.bin

# Input device configs
PRODUCT_COPY_FILES += \
    vendor/lenovo/yogabook/proprietary/idc/yogabook.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/yogabook.idc \
    vendor/lenovo/yogabook/proprietary/keylayout/yogabook.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/yogabook.kl \
    vendor/lenovo/yogabook/proprietary/keychars/yogabook.kcm:$(TARGET_COPY_OUT_VENDOR)/usr/keychars/yogabook.kcm

# Sensors configuration
PRODUCT_COPY_FILES += \
    vendor/lenovo/yogabook/proprietary/sensors/hubd.conf:$(TARGET_COPY_OUT_VENDOR)/etc/sensors/hubd.conf

# HaloKeyboard firmware/config
PRODUCT_COPY_FILES += \
    vendor/lenovo/yogabook/proprietary/halokeyboard/firmware.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/halokeyboard_firmware.bin