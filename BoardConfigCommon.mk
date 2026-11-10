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
# 【解密关键】S-Boot 会把 boot 镜像头部的 os_version 字段直接交给 TEE 的 keymaster
# （日志：tz_init_bootloader_info: os_version : 160000 -> swd_configure:
#  invalid os_version or os_patchlevel -> km_check_key_os_version_patchlevels 拒绝解封
#  /metadata 的密钥 -> Unable to decrypt metadata encryption -> /data 挂不上）。
# 这条信息来自镜像头，resetprop 改属性完全无效。
# 本机 ROM 是 Android 17，所以这里追加（追加在构建系统自己的 --os_version 16 之后，
# mkbootimg 取最后一次的值）。
BOARD_MKBOOTIMG_ARGS += --os_version 17 --os_patch_level 2026-10-01

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
# 必须开启：三星 bootloader 在启动时会校验 recovery 分区的 AVB footer。
# 实测能正常引导的第三方 recovery（Rocky7842 / crDroid 官方）在文件末尾 64 字节
# 都有 "AVBf" footer，original_image_size = 内容实际大小，并填充到分区大小；
# 而未签名的 recovery.img 会卡在三星 LOGO（内核都来不及运行）。
BOARD_AVB_ENABLE := true
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
# 与可用镜像（crDroid/Rocky7842）完全一致：其 vbmeta 里 Rollback Index Location = 0
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 0

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

# 本机为 A-only（有独立 recovery 分区，无 boot_a/boot_b）。
# AOSP 的 build/make/core/board_config.mk 在 AB_OTA_UPDATER 为空时会默认置 true，
# 后果有二：OrangeFox 误判为 A/B 设备（FOX_AB_DEVICE=1，见 bootable/recovery/orangefox.mk:165），
# 以及 update_engine_sideload（3.0 MB）被塞进 recovery ramdisk。故显式设为 false。
AB_OTA_UPDATER := false

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
# 体积控制（recovery.img 必须 <= 67,633,152 B）。注意两个不同的判断语义：
#   - REPACKTOOLS / FASTBOOTD 用 ifneq (,$(filter $(X),true)) 判断 -> 写 false 有效；
#   - LPDUMP / LPTOOLS 用 ifneq ($(X),) 判断 -> 写 false 反而等于"启用"！必须留空。
# 关闭 LPDUMP 连带去掉 lpdump / lpdumpd / liblpdump.so / libprotobuf-cpp-full.so（约 2.5 MB）。
TW_INCLUDE_REPACKTOOLS := false
TW_INCLUDE_LPDUMP :=
TW_INCLUDE_LPTOOLS :=
# 只要 PRODUCT_USE_DYNAMIC_PARTITIONS=true，fastbootd 就会被强制带入
# （bootable/recovery/prebuilt/Android.mk:45），此处保留 false 仅作说明。
TW_INCLUDE_FASTBOOTD := false
# 打入 zoneinfo/tzdata（约 407 KB，压缩后约 200 KB）：默认时区已由
# OF_DEFAULT_TIMEZONE := CST-8（POSIX 写法，不依赖文件）保证为中国时间，
# 这里再把 tzdata 带上，使时区"选择列表"可用，并消除 __bionic_open_tzdata 报错。
# 体积余量：分区 67,633,152 - AVB 69,632 - 当前内容 66,979,840 = 583,680 B。
TW_EXCLUDE_TZDATA := false
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

-include vendor/lineage/config/BoardConfigReservedSize.mk

# ---------------------------------------------------------------------------
# 引入 LineageOS 的 BoardConfig 公共配置（内核 + soong 变量导出）
#
# 本设备树最初只 include 了 BoardConfigReservedSize.mk，漏掉了这一行。
# 后果（2026-11-11 实测）：vendor/lineage/config/BoardConfigKernel.mk 里定义的
#   KERNEL_MAKE_CMD / KERNEL_MAKE_FLAGS / KERNEL_BUILD_OUT_PREFIX
# 全部为空；BoardConfigSoong.mk 把这些空值导出给 soong，而 soong 把空值当作
# "未定义"，于是解析 vendor/lineage/build/soong/Android.bp 里的
# generated_kernel_includes 时报：
#     cmd: unknown variable '$(KERNEL_BUILD_OUT_PREFIX)'
# 整个 ROM 构建就此卡死。补上这一行后上述变量全部有值。
# ---------------------------------------------------------------------------
include vendor/lineage/config/BoardConfigLineage.mk
