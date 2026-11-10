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

# fastbootd 及 mock HAL 已关闭（TW_INCLUDE_FASTBOOTD := false）：
# recovery.img 受 67,633,152 字节分区上限约束，ramdisk 经 LZMA 压缩后仍需腾出空间。
# 若以后需要 fastbootd 刷写逻辑分区，把下面这段和 BoardConfigCommon.mk 里的
# TW_INCLUDE_FASTBOOTD 一起恢复即可。
# PRODUCT_PACKAGES += \
#     android.hardware.fastboot@1.0-impl-mock \
#     fastbootd
#
# PRODUCT_PRODUCT_PROPERTIES += \
#     ro.fastbootd.available=true

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

# ---------------------------------------------------------------------------
# VoLTE / IMS 强制开启（D2+D3）
#
# 现象：本机 SIM 为中国联通 46001，语音/数据都 IN_SERVICE、IMS 进程也都在跑，
#       但电话打不通、短信发不出。原因是：
#         - ro.carrier = unknown（三星韩国固件遗留 ro.boot.carrierid=KOO）
#           → 匹配不到 46001 的 carrier config，落到默认值
#         - 默认值里 carrier_volte_available_bool = false
#         - 且 modem 上报 mVopsSupport = 2 (LTE_STATUS_NOT_SUPPORTED)
#       联通已无 2G/3G 兜底，所以没有 VoLTE 就没有任何通话承载。
#
# 运行期 `setprop persist.dbg.ims_volte_enable 1` 会被权限拒绝，
# 因此改为构建期写入默认属性（init 以 root 身份设置，不会被拒绝）。
# ---------------------------------------------------------------------------
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    persist.dbg.ims_volte_enable=1 \
    persist.dbg.ims_volte_enable_vt=1 \
    persist.dbg.vt_avail_on=1 \
    persist.dbg.vt_avail_on_ext=1 \
    persist.radio.calls.on.ims=1 \
    persist.radio.jbims=1 \
    persist.dbg.volte_avail_ovr=1 \
    persist.dbg.wfc_avail_ovr=1 \
    ro.carrier=CHN-CHINA-UNICOM \
    ro.vendor.ims_support=1
