# OrangeFox Recovery 公共设备树 —— 三星 Exynos 9820 / 9825

供 [OrangeFox Recovery](https://orangefox.tech) 的三星 Exynos 9820（Galaxy S10 系列）与
Exynos 9825（Galaxy Note10 系列）设备树共用。

当前分支 **fox_16.0**，AOSP 16 底座，lunch 目标形如 `twrp_d1x-bp2a-eng`。

| 设备 | 代号 | 设备树 |
| :-- | :-- | :-- |
| Galaxy S10e | beyond0lte | 上游 Exynos982x-OrangeFox |
| Galaxy S10 | beyond1lte | 上游 Exynos982x-OrangeFox |
| Galaxy S10+ | beyond2lte | 上游 Exynos982x-OrangeFox |
| Galaxy S10 5G | beyondx | 上游 Exynos982x-OrangeFox |
| Galaxy Note10 | d1 | 上游 Exynos982x-OrangeFox |
| **Galaxy Note10 5G（韩版 SM-N971N）** | **d1x** | [android_device_samsung_d1x](https://github.com/mcajun87/android_device_samsung_d1x)（本仓库配套树） |
| Galaxy Note10+ | d2s | 上游 Exynos982x-OrangeFox |
| Galaxy Note10+ 5G | d2x | 上游 Exynos982x-OrangeFox |
| Galaxy F62 | f62 | 上游 Exynos982x-OrangeFox |

## 内核要求（重要）

本树使用**预编译内核**（各设备树 `prebuilt/Image`），因为内核由设备树各自维护。
内核必须满足：

| 配置 | 原因 |
| :-- | :-- |
| `CONFIG_RD_LZMA=y`（或 GZIP/XZ/LZ4） | 本树启用 `LZMA_RAMDISK_TARGETS := recovery`，内核需能解压 ramdisk |
| `CONFIG_IKCONFIG=y` + `CONFIG_IKCONFIG_PROC=y` | A16 的 `check_vintf` 需从内核镜像提取 config；缺失时会中断构建 |
| `CONFIG_LEDS_S2MPB02=y` | 三星闪光灯驱动 |
| Android 12+ 固件的 Keymaster 4.0 | 解密流程依赖（见下） |

若内核缺少 `IKCONFIG`，可在设备树的 `device-common.mk` 里用官方开关跳过：

```makefile
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false
```

（本仓库当前已设为 `false`，因为部分预编译内核未嵌入 config。）

## 解密流程（FBE + metadata 加密）

三星 Exynos 设备的 `/data` 解密需要 ROM 自带的 TEE 组件，本树通过
`recovery/root/` 下的文件实现：

```
system/etc/init/exynos9820-common.rc   ← 启动 tzdaemon / tzts_daemon / keymaster / gatekeeper
system/bin/prepdecrypt.sh             ← 从 ROM 的 system/vendor 读取 OS 版本与安全补丁，resetprop
vendor/etc/vintf/manifest.xml         ← 声明 keymaster@4.0 与 gatekeeper@1.0
```

对应 BoardConfig 配置：

| 配置 | 值 |
| :-- | :-- |
| `TW_INCLUDE_CRYPTO` | `true` |
| `TW_INCLUDE_CRYPTO_FBE` | `true` |
| `TW_INCLUDE_FBE_METADATA_DECRYPT` | `true` |
| `TW_USE_FSCRYPT_POLICY` | `2` |
| `OF_DEFAULT_KEYMASTER_VERSION` | `4.0`（与 rc 里启动的 `@4.0-service.samsung` 一致） |

若真机解密失败，按序尝试：`4.1` → `4.1` + `TW_FORCE_KEYMASTER_VER := true` →
加 `OF_NO_KEYMASTER_VER_4X := 1`。

## 手电筒

OrangeFox 的手电筒把 `OF_FL_PATH1` 当作 **LED class 目录**，自行拼接
`<path>/brightness` 与 `<path>/max_brightness`（`gui/action.cpp:2646-2648`）。

本树的 `exynos9820-common.rc` 已经准备好这个目录：

```rc
mkdir /dev/fox_flash
symlink /sys/class/camera/flash/rear_flash /dev/fox_flash/brightness
```

因此 `OF_FL_PATH1 := /dev/fox_flash`。**不要填 sysfs 属性节点本身**
（如 `/sys/class/camera/flash/rear_flash`），否则会去找 `.../rear_flash/brightness`
而报 `Flashlight file not found!`。

该软链依赖内核保留 `camera_class`（即 `device_create(camera_class, ...)`）。
若内核改掉了 `camera_class`，`/sys/class/camera/flash/rear_flash` 将不存在，
需要相应修改 rc 里的软链目标。

## 分区与备份

`recovery.fstab` 只放**需要挂载**的分区（system/vendor/data/metadata/misc 等）；
需要出现在 TWRP 备份/刷写列表里的分区统一写在
`recovery/root/system/etc/twrp.flags`：

```
/boot /recovery /dtbo /dtb /vbmeta /modem
/efs /sec_efs /keydata /keyrefuge
/sdcard1（MicroSD） /usb_otg（U 盘）
```

**不要在 `recovery.fstab` 里重复定义这些挂载点**，否则会出现重复条目。
（注意三星的 `/metadata` 使用 `omr` 分区；dynamic partitions 元数据在 `system` 上，
对应 `androidboot.super_partition=system`。）

## 构建

```sh
git clone https://gitlab.com/OrangeFox/sync.git
cd sync
./orangefox_sync.sh --branch 16.0 --path ~/fox_16.0   # 需要 sync 脚本 v030+

cd ~/fox_16.0
git clone -b fox_16.0 https://github.com/mcajun87/android_device_samsung_d1x device/samsung/d1x
git clone -b fox_16.0 https://github.com/mcajun87/android_device_samsung_exynos9820-common device/samsung/exynos9820-common

export FOX_BUILD_DEVICE=d1x
export ALLOW_MISSING_DEPENDENCIES=true
source build/envsetup.sh
lunch twrp_d1x-bp2a-eng

# A16 必须显式导出，否则 make 会回落到 trunk_staging 兜底值并报
# "release-config failed to run / panic: Missing config trunk_staging"
export TARGET_PRODUCT=twrp_d1x
export TARGET_RELEASE=bp2a
export TARGET_BUILD_VARIANT=eng

mka adbd recoveryimage
```

## 编译树注意事项

本树依赖 AOSP 的 `prebuilts/clang/host/linux-x86`：

- 该项目的上游 `Android.bp` 定义了 49 个模块（含 `llvm_prebuilt_*`、
  `libclang_rt_prebuilt_*` 等自定义模块类型），需要同项目的 `soong/` 插件目录
  （`soong-clang-prebuilts`，已列入 `build/soong/android/plugin.go` 白名单）。
- 若该项目未完整 `repo sync`，会出现
  `module libc missing dependencies: libunwind-exported`、
  `missing and no known rule: libclang_rt.ubsan_minimal.a`、
  `Unable to find libclang`（bindgen）一类报错。
  根治办法：`repo sync prebuilts/clang/host/linux-x86`；
  临时办法见设备树仓库的 `patches/`。
- `build/soong/rust/bindgen.go` 把 bindgen 的内核钉在 `clang-r530567`。
  若本机只有其他版本，可为缺失版本号建立指向现有工具链的符号链接。

## Credits

- [ExtremeXT](https://github.com/ExtremeXT/android_device_samsung_exynos9820) —— TWRP 设备树原型
- [LineageOS](https://github.com/LineageOS/android_device_samsung_exynos9820-common) —— 平台配置与内核
