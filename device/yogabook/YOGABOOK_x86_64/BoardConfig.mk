#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit the LineageOS mainline generic x86_64 board config
# (kernel pipeline, GRUB boot manager targets, Mesa, cmdline, ...).
include device/mainline/generic/Generic_x86_64/BoardConfig.mk

# Append the Yoga Book hardware fragment to the kernel config pipeline.
# (Generic_x86_64 assembles: pre-debian.config + debian-filtered.config +
#  fix-build.config + fbcon.config + customizations.config)
TARGET_KERNEL_CONFIG_EXT += \
    device/yogabook/YOGABOOK_x86_64/configs/kernel/yogabook.config
