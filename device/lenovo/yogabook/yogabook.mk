# Yoga Book YB1-91F Device Configuration
# Inherit from the common Open Source product configuration
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_base_telephony.mk)

# Inherit from hardware-specific part of the product configuration
$(call inherit-product, device/lenovo/yogabook/device-yogabook.mk)

# Device identifier. This must come after all inclusions
PRODUCT_DEVICE := yogabook
PRODUCT_NAME := aosp_yogabook
PRODUCT_BRAND := Lenovo
PRODUCT_MODEL := Yoga Book YB1-91F
PRODUCT_MANUFACTURER := Lenovo

# Boot animation
TARGET_SCREEN_HEIGHT := 1200
TARGET_SCREEN_WIDTH := 1920

# Enable updating of APEXes
$(call inherit-product, $(SRC_TARGET_DIR)/product/updatable_apex.mk)

# Proprietary blob setup
$(call inherit-product-if-exists, vendor/lenovo/yogabook/yogabook-vendor.mk)