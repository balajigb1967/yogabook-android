#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base.mk)

# Inherit some common Lineage stuff (tablet, Wi-Fi only).
$(call inherit-product, vendor/lineage/config/common_full_tablet_wifionly.mk)

# Inherit the LineageOS mainline generic x86_64 device (kernel, init, HALs).
$(call inherit-product, device/mainline/generic/Generic_x86_64/device.mk)

# Yoga Book additions (halo keyboard, diagnostics, audio, ISO packaging).
$(call inherit-product, device/yogabook/YOGABOOK_x86_64/device.mk)

PRODUCT_NAME := lineage_YOGABOOK_x86_64
PRODUCT_DEVICE := YOGABOOK_x86_64
PRODUCT_BRAND := Lenovo
PRODUCT_MODEL := Yoga Book YB1-X9x
PRODUCT_MANUFACTURER := Lenovo

# Keep build fingerprint generic enough that nothing phones home as a
# certified device; Play certification is handled by the user (docs/gapps.md).
PRODUCT_PROPERTY_OVERRIDES += \
    ro.yogabook.build=1 \
    ro.build.characteristics=tablet
