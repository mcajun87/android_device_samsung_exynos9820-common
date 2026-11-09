#
# Copyright (C) 2024 The TWRP Open Source Project
# Copyright (C) 2026 The OrangeFox Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

PRODUCT_SHIPPING_API_LEVEL ?= 28

PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_BUILD_SUPER_PARTITION := false

PRODUCT_PACKAGES += \
    android.hardware.fastboot@1.0-impl-mock \
    fastbootd

PRODUCT_PRODUCT_PROPERTIES += \
    ro.fastbootd.available=true

# 使用预编译内核 Image，未启用 CONFIG_IKCONFIG，镜像里没有可提取的内核 config。
# A16 的 check_vintf 会尝试从内核镜像提取 config 做 VINTF 内核要求校验，
# 提取失败会中断构建（Cannot extract kernel configs）。
# shellcheck 掉的开关：本设备不需要 OTA 级内核 VINTF 校验。
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

# 本系列设备的 kernel 使用 4 KiB 页（Exynos 9820/9825，Android 12 基座），
# 但 A16 默认会检查预编译 ELF 是否按 16 KiB 页对齐，
# 导致上游 Magisk 预编译的 magiskboot 被拒：
#   error: Load segment has alignment 4096 but 16384 required.
# AOSP 的报错本身给出的设备级官方解法就是：
#   PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE := false
PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE := false
