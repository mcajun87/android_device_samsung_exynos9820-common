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
