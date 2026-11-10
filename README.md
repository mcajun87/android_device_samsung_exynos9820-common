# OrangeFox 公共配置 — Samsung Exynos 9825 / d1x

本仓库是 [android_device_samsung_d1x](https://github.com/mcajun87/android_device_samsung_d1x)
（Galaxy Note10 5G / SM-N971N）的公共配置树，分支 `fox_16.0`（AOSP 16 底座）。

> **只服务 d1x 一个型号。** 本树源自 Exynos982x 系列公共树，但已按 d1x 单机型维护，
> beyond0lte / beyond1lte / beyond2lte / beyondx / d1 / d2s / d2x / f62 等
> 其他型号的说明与支持已全部移除。

---

## 本树负责什么

| 内容 | 文件 |
| :-- | :-- |
| 板级配置（分区、内核/DTBO、AVB、加密、体积） | `BoardConfigCommon.mk` |
| 产品包与属性 | `device-common.mk` |
| 分区挂载表 | `recovery.fstab` |
| 分区标志（备份/刷写/显示名） | `recovery/root/system/etc/twrp.flags` |
| 解密流程（TEE / keymaster / gatekeeper 拉起） | `recovery/root/system/etc/init/exynos9820-common.rc` |
| 解密前准备（读 ROM 版本、搬 TEE 组件、同步属性） | `recovery/root/system/bin/prepdecrypt.sh` |
| USB 配置 | `recovery/root/init.recovery.usb.rc` |

---

## 三个必须知道的实测结论

### 1. 解密：`os_version` 必须来自 boot 头部，且等于 ROM 版本

`/data` 使用**元数据加密**（`metadata_encryption=aes-256-xts`，密钥目录
`/metadata/vold/metadata_encryption`），因此**不需要用户密码**——只要 keymaster
能解封元数据密钥，开机就会自动挂载。

失败时 TWRP 只有一行 `I:Unable to decrypt metadata encryption`，真正的证据在
TEE 的 keymaster 日志里：

```
SW> keymaster (tz_init_bootloader_info:1066) os_version : 160000
SW> keymaster (swd_configure:106)  invalid os_version or os_patchlevel
SW> keymaster (km_check_key_os_version_patchlevels:194) key_os_version(170000) > _os_version(160000)
-> I:Unable to decrypt metadata encryption -> /data 挂不上 -> MTP 也不可用
```

这个 `160000` 来自 **boot 镜像头部字段**（S-Boot 转交 TEE）。把
`ro.build.version.release` 等属性全改成 17、重启 keymaster，TEE **依然报 160000**。
所以必须在构建时写：

```makefile
BOARD_MKBOOTIMG_ARGS += --os_version 17 --os_patch_level 2026-10-01
```

（追加在构建系统默认的 `--os_version 16` 之后；mkbootimg 取最后一次的值。）

`prepdecrypt.sh` 另外把 `ro.system.build.*` / `ro.product.build.*` /
`ro.odm.build.*` 同步成 ROM 的值，作为二次保险。

### 2. 手电筒：只能用三星私有节点

| 路径 | 行为 | 可用性 |
| :-- | :-- | :-- |
| `/sys/class/leds/torch-sec1/brightness` | 读写一致（0~15），**写进去不亮** | ❌ |
| `/sys/class/camera/flash/rear_flash` | 只认 `0/1/100/1001~1010/2000~2015`，读值恒为 15 | ✅ 唯一能亮 |

`recovery/root/system/etc/init/exynos9820-common.rc` 里：

```
mkdir /dev/fox_flash 0755 root root
symlink /sys/class/camera/flash/rear_flash /dev/fox_flash/brightness
write /dev/fox_flash/max_brightness 100
```

`max_brightness` 用 init 的 `write`（底层 `WriteFile` 带 `O_CREAT`）在 tmpfs 里生成，
内容 `100` = 工厂手电档 240 mA。**若缺失**，OrangeFox 会退化写 `1`（60 mA，几乎看不见）。

### 3. 体积：`TW_INCLUDE_*` 有两种判断语义

`bootable/recovery/prebuilt/Android.mk` 混用两种写法，写 `false` 的后果完全不同：

```make
# (1) false 有效
ifneq ($(filter $(PRODUCT_USE_DYNAMIC_PARTITIONS) $(TW_INCLUDE_FASTBOOTD),true),)

# (2) 非空即真 —— 写 false 等于"启用"！必须留空
ifneq ($(TW_INCLUDE_LPDUMP),)
ifneq ($(TW_INCLUDE_LPTOOLS),)
```

本树写法：

```make
TW_INCLUDE_REPACKTOOLS := false
TW_INCLUDE_LPDUMP :=
TW_INCLUDE_LPTOOLS :=
TW_INCLUDE_FASTBOOTD := false   # 但 PRODUCT_USE_DYNAMIC_PARTITIONS=true 时仍会带入 fastbootd
```

另外 AOSP 的 `board_config.mk` 在 `AB_OTA_UPDATER` 为空时默认置 `true`，
会让 OrangeFox 把 A-only 设备当 A/B 设备（`FOX_AB_DEVICE=1`）并白塞
3 MB 的 `update_engine_sideload`，所以本树显式写死：

```makefile
AB_OTA_UPDATER := false
```

### 体积账（实测）

| 项目 | 未压缩 | 说明 |
| :-- | --: | :-- |
| `update_engine_sideload` + `bootctl` | ≈3,134,000 | `AB_OTA_UPDATER := false` 去掉 |
| `lpdump`/`lpdumpd`/`liblpdump*`/`libprotobuf-cpp-full` | 2,552,328 | `TW_INCLUDE_LPDUMP :=` 留空去掉 |
| 内核 `-O2` → `-Os` | — | 49,059,864 → 47,601,688（省 1,458,176） |
| ramdisk 压缩 `lzma -6` → `-9` | — | 18,449,104 → 16,599,792（省 1,849,312） |

---

## 内核要求

| 配置 | 原因 |
| :-- | :-- |
| `CONFIG_RD_LZMA=y`（或 GZIP/XZ/LZ4） | 本树启用 `LZMA_RAMDISK_TARGETS := recovery` |
| `CONFIG_LEDS_S2MPB02=y` | 三星闪光灯 / 手电筒驱动 |
| `CONFIG_IKCONFIG=y` + `CONFIG_IKCONFIG_PROC=y` | A16 的 `check_vintf` 需从内核镜像提取 config |

内核缺 `IKCONFIG` 时，本树已在 `device-common.mk` 里关掉强制校验：

```makefile
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false
```

---

## 解密失败时的排查顺序

1. 看 TEE 日志：`dmesg | grep -E "keymaster|tz_init|swd_configure"`，
   确认 `os_version` 是否已是 `170000`
2. 确认 `/metadata` 已挂载、`/metadata/vold/metadata_encryption/key` 存在
3. 确认 keymaster / gatekeeper 服务在跑：
   `getprop init.svc.vendor.keymaster-4-0`、`getprop init.svc.vendor.gatekeeper-1-0`
4. 确认 `prepdecrypt.status=done`
5. 真机解密失败的备选配置：`OF_DEFAULT_KEYMASTER_VERSION := 4.1` →
   再加 `TW_FORCE_KEYMASTER_VER := true` → 再加 `OF_NO_KEYMASTER_VER_4X := 1`
