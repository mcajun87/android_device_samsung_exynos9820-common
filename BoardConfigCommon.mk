#
# Copyright (C) 2024 The TWRP Open Source Project
# Copyright (C) 2026 The OrangeFox Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#

COMMON_PATH := device/samsung/exynos9820-common

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a-dotprod
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a75

# Bootloader
TARGET_NO_BOOTLOADER := true
BOARD_VENDOR := samsung

# Kernel
TARGET_KERNEL_ARCH := arm64
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/$(BOARD_KERNEL_IMAGE_NAME)
BOARD_INCLUDE_RECOVERY_DTBO := true
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img

BOARD_KERNEL_BASE := 0x10000000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x01000000
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_BOOTIMG_HEADER_VERSION ?= 1
# OrangeFox/TWRP 读取的是 BOARD_BOOT_HEADER_VERSION（注意与 AOSP 的
# BOARD_BOOTIMG_HEADER_VERSION 是两个不同变量名）。不设置时
# bootable/recovery/orangefox.mk 会告警并自行默认 v1，显式声明以消除歧义。
BOARD_BOOT_HEADER_VERSION := 1
BOARD_MKBOOTIMG_ARGS := \
    --base $(BOARD_KERNEL_BASE) \
    --pagesize $(BOARD_KERNEL_PAGESIZE) \
    --kernel_offset $(BOARD_KERNEL_OFFSET) \
    --ramdisk_offset $(BOARD_RAMDISK_OFFSET) \
    --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) \
    --header_version $(BOARD_BOOTIMG_HEADER_VERSION)

# The physical system partition holds the dynamic partitions metadata
BOARD_KERNEL_CMDLINE ?= androidboot.super_partition=system

# Partitions
BOARD_FLASH_BLOCK_SIZE := 4096
BOARD_RECOVERYIMAGE_PARTITION_SIZE ?= 67633152
BOARD_DTBOIMG_PARTITION_SIZE := 8388608
BOARD_USES_METADATA_PARTITION := true

BOARD_ROOT_EXTRA_FOLDERS := \
    efs \
    keydata \
    keyrefuge \
    vendor_rom

BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_ODM := odm

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS := true

# Android Verified Boot
# recovery.img 不做 AVB 签名：
#   1) 三星 bootloader 不信任 AOSP testkey，签了也不会通过校验；
#   2) crDroid d1x 官方 recovery.img 实测无 AVB footer（dtbo 紧接 ramdisk）；
#   3) 保留 AVB 会改变镜像布局，与已知可用镜像不一致。

# Security patch level
# 注意：A16 的 PLATFORM_VERSION 由 release config（本树 lunch 用 bp2a -> 16）提供。
# 旧 fox_12.1 树的 "PLATFORM_VERSION := 99.87.36" 属于 TWRP-12.x 时代的 hack，
# 在 A16 上会让 PLATFORM_VERSION 与 PLATFORM_VERSION_LAST_STABLE 自相矛盾，
# 故此处不再覆盖版本号，仅保留补丁级别。
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)

# Recovery
TARGET_RECOVERY_FSTAB ?= $(COMMON_PATH)/recovery.fstab
TARGET_RECOVERY_DEVICE_DIRS += $(COMMON_PATH)
TARGET_RECOVERY_PIXEL_FORMAT := ABGR_8888
RECOVERY_SDCARD_ON_DATA := true
BOARD_SUPPRESS_SECURE_ERASE := true

# OrangeFox UPX-packs the ramdisk executables; a packed init needs execmem,
# which its vendor_init subcontext lacks, so unpack init and keystore2 again.
BOARD_RECOVERY_IMAGE_PREPARE += \
    for f in init keystore2; do \
        vendor/recovery/tools/upx -q -d $(TARGET_RECOVERY_ROOT_OUT)/system/bin/$$f >/dev/null 2>&1 || true; \
    done;

# Encryption
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
TW_USE_FSCRYPT_POLICY := 2
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_LIBRESETPROP := true

# TWRP
TW_THEME := portrait_hdpi
TW_BRIGHTNESS_PATH := "/sys/class/backlight/panel/brightness"
TW_MAX_BRIGHTNESS := 25500
TW_DEFAULT_BRIGHTNESS := 12800
TW_NO_REBOOT_BOOTLOADER := true
TW_HAS_DOWNLOAD_MODE := true
TW_USE_SERIALNO_PROPERTY_FOR_DEVICE_ID := true
TW_BACKUP_EXCLUSIONS := /data/fonts/files
TW_EXCLUDE_APEX := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_ENABLE_FS_COMPRESSION := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_LPDUMP := true
TW_INCLUDE_LPTOOLS := true
TW_INCLUDE_FASTBOOTD := true
TW_EXCLUDE_TZDATA := true
TW_EXCLUDE_NANO := true
TW_EXCLUDE_BASH := true
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true

# Languages
# 简体中文为默认语言；TW_EXTRA_LANGUAGES=true 才会把
# gui/theme/extra-languages/ 打包进 ramdisk（zh_CN / zh_TW 都在那里）。
# 英文由 gui/theme/common/languages/en.xml 提供，始终存在。
TW_DEFAULT_LANGUAGE := zh_CN
TW_EXTRA_LANGUAGES := true

# 默认时区：中国标准时间（UTC+8，无夏令时）
# OrangeFox 该变量是 POSIX TZ 串（data.cpp:672 直接 setenv("TZ", ...)），
# 不是 "Asia/Shanghai"。源码默认值是中欧时间 CET-1;CEST,M3.5.0,M10.5.0，
# 必须显式覆盖，否则恢复出厂后时区会变成欧洲。
# 写入位置：tw_time_zone / tw_time_zone_guisel / persist.sys.timezone
OF_DEFAULT_TIMEZONE := CST-8

# OrangeFox
OF_MAINTAINER := mcajun87
# 解密（必须）：FBE + metadata 加密 + fscrypt policy v2
# std::property twrp.keymaster_version 会被设为该值。
# 若真机解密失败（报 keymaster 相关错误），按以下顺序试：
#   a) OF_DEFAULT_KEYMASTER_VERSION := 4.1
#   b) OF_DEFAULT_KEYMASTER_VERSION := 4.1  +  TW_FORCE_KEYMASTER_VER := true
#   c) 加 OF_NO_KEYMASTER_VER_4X := 1（禁用 4.x 支持，回退 keymaster 3）
OF_DEFAULT_KEYMASTER_VERSION := 4.0
OF_USE_LZMA_COMPRESSION := 1
LZMA_RAMDISK_TARGETS := recovery
OF_NO_TREBLE_COMPATIBILITY_CHECK := 1
OF_QUICK_BACKUP_LIST := /boot;/data;
OF_SCREEN_H := 2280
OF_STATUS_INDENT_LEFT := 48
OF_STATUS_INDENT_RIGHT := 48
OF_CLOCK_POS := 1
OF_HIDE_NOTCH := 1
OF_ALLOW_DISABLE_NAVBAR := 0
OF_FLASHLIGHT_ENABLE := 1
# OF_FL_PATH1 是【LED class 目录】，不是 sysfs 属性节点本身。
# OrangeFox 会拼接 "<OF_FL_PATH1>/brightness" 与 "<OF_FL_PATH1>/max_brightness"
# （bootable/recovery/gui/action.cpp:2646-2648），找不到就打印
# "Flashlight file not found!" 并直接返回。
# 本树的 recovery/root/system/etc/init/exynos9820-common.rc 会创建该目录：
#     mkdir /dev/fox_flash
#     symlink /sys/class/camera/flash/rear_flash /dev/fox_flash/brightness
# 所以这里必须填目录 /dev/fox_flash；填 /sys/class/camera/flash/rear_flash
# 会变成去找 ".../rear_flash/brightness"（不存在），手电筒失效。
OF_FL_PATH1 := /dev/fox_flash
