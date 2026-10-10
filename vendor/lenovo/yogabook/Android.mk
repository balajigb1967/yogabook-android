# Yoga Book YB1-91F Vendor Makefile
# This file defines vendor-specific modules to be built

LOCAL_PATH := $(call my-dir)

# HaloKeyboard HAL
include $(CLEAR_VARS)
LOCAL_MODULE := android.hardware.halokeyboard@1.0-service
LOCAL_SRC_FILES := halokeyboard.cpp
LOCAL_SHARED_LIBRARIES := \
    liblog \
    libhidlbase \
    libhidltransport \
    libhwbinder
LOCAL_INIT_RC := halokeyboard.rc
LOCAL_PROPRIETARY_MODULE := true
include $(BUILD_EXECUTABLE)

# Sensor Hub HAL
include $(CLEAR_VARS)
LOCAL_MODULE := android.hardware.sensors@2.0-service.yogabook
LOCAL_SRC_FILES := sensors.cpp
LOCAL_SHARED_LIBRARIES := \
    liblog \
    libhidlbase \
    libhidltransport \
    libhwbinder
LOCAL_INIT_RC := sensors.rc
LOCAL_PROPRIETARY_MODULE := true
include $(BUILD_EXECUTABLE)

# Audio HAL (RT5677)
include $(CLEAR_VARS)
LOCAL_MODULE := android.hardware.audio@6.0-service.yogabook
LOCAL_SRC_FILES := audio_hal.cpp
LOCAL_SHARED_LIBRARIES := \
    liblog \
    libhidlbase \
    libhidltransport \
    libhwbinder \
    libaudioroute \
    libaudiohal \
    libtinyalsa \
    libdl
LOCAL_INIT_RC := audio.rc
LOCAL_PROPRIETARY_MODULE := true
include $(BUILD_EXECUTABLE)

# Camera HAL
include $(CLEAR_VARS)
LOCAL_MODULE := android.hardware.camera.provider@2.4-service.yogabook
LOCAL_SRC_FILES := camera_hal.cpp
LOCAL_SHARED_LIBRARIES := \
    liblog \
    libhidlbase \
    libhidltransport \
    libhwbinder \
    libbinder \
    libutils \
    libcutils
LOCAL_INIT_RC := camera.rc
LOCAL_PROPRIETARY_MODULE := true
include $(BUILD_EXECUTABLE)

# Copy proprietary firmware and configs
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/firmware/RT5677/rt5677_dsp.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/rt5677_dsp.bin \
    $(LOCAL_PATH)/firmware/camera/mbm_firmware.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/mbm_firmware.bin \
    $(LOCAL_PATH)/firmware/wifi/rtl8723bs_fw.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/rtl8723bs_fw.bin \
    $(LOCAL_PATH)/firmware/bluetooth/rtl8723bs_bt.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/rtl8723bs_bt.bin \
    $(LOCAL_PATH)/ucm/RT5677:$(TARGET_COPY_OUT_VENDOR)/share/alsa/ucm/RT5677 \
    $(LOCAL_PATH)/idc/yogabook.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/yogabook.idc \
    $(LOCAL_PATH)/keylayout/yogabook.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/yogabook.kl \
    $(LOCAL_PATH)/keychars/yogabook.kcm:$(TARGET_COPY_OUT_VENDOR)/usr/keychars/yogabook.kcm