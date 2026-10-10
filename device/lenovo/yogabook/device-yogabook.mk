# Yoga Book YB1-91F Device Configuration
# This file contains the device-specific configurations

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a73

# Kernel configuration
TARGET_KERNEL_SOURCE := kernel/lenovo/yogabook
TARGET_KERNEL_CONFIG := yogabook_defconfig
BOARD_KERNEL_IMAGE_NAME := Image.gz
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_RAMDISK_OFFSET := 0x01000000
BOARD_KERNEL_SEPARATED_DTBO := true

# Platform
TARGET_BOARD_PLATFORM := cherrytown
TARGET_BOOTLOADER_BOARD_NAME := yogabook

# Filesystem
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 67108864
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 3221225472
BOARD_USERDATAIMAGE_PARTITION_SIZE := 57671680000
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_CACHEIMAGE_PARTITION_SIZE := 268435456

# Workaround for error avoiding vendor files
BOARD_VNDK_VERSION := current
PRODUCT_COMPATIBLE_PROPERTY_OVERRIDE := true

# Treble
PRODUCT_FULL_TREBLE_OVERRIDE := true
PRODUCT_VENDOR_MOVE_ENABLED := true
TARGET_COPY_OUT_VENDOR := vendor

# A/B support
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    system \
    vendor \
    vbmeta \
    vbmeta_system

# HIDL
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := \
    device/lenovo/yogabook/framework_compatibility_matrix.xml \
    vendor/lenovo/yogabook/vndk.yaml \
    hardware/google/pixel/compatibility_matrix.xml

DEVICE_MANIFEST_FILE := \
    device/lenovo/yogabook/manifest.xml

DEVICE_MATRIX_FILE := \
    device/lenovo/yogabook/compatibility_matrix.xml

# Boot animation
TARGET_SCREEN_HEIGHT := 1200
TARGET_SCREEN_WIDTH := 1920

# Audio
USE_XML_AUDIO_POLICY_CONF := 1
BOARD_USES_ALSA_AUDIO := true
BOARD_USES_GENERIC_AUDIO := false

# Bluetooth
BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR := device/lenovo/yogabook/bluetooth

# Camera
TARGET_USES_QTI_CAMERA_DEVICE := true
BOARD_QTI_CAMERA_32BIT_ONLY := false

# Display
TARGET_SCREEN_DENSITY := 224

# HaloKeyboard
BOARD_HALO_KEYBOARD_SUPPORT := true

# Sensors
BOARD_USES_SENSOR_HUB := true

# Properties
TARGET_SYSTEM_PROP += device/lenovo/yogabook/system.prop
TARGET_VENDOR_PROP += device/lenovo/yogabook/vendor.prop
TARGET_PRODUCT_PROP += device/lenovo/yogabook/product.prop