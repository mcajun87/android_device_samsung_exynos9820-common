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


## 继承自 fox_12.1 的文件：离线验证结论

以下文件原样继承自上游 fox_12.1 树，未做修改。已用**可验证的实物证据**逐项核对，
结论是不需要改动（供以后排查时参考，避免重复怀疑）：

| 项 | 结论 | 证据来源 |
| :-- | :-- | :-- |
| `twrp.flags` 中 `/modem` → `by-name/radio` | ✅ 分区名正确 | ROM `updater-script` 第 125 行：`package_extract_file("firmware/SM-N971N/modem.bin", "/dev/block/by-name/radio")` |
| `13d60000.ufs` 这个平台路径 | ✅ 在 d1x 上真实存在 | 同一 `updater-script` 第 95 行：`package_extract_file("boot.img", "/dev/block/platform/13d60000.ufs/by-name/boot")` |
| `TARGET_OTA_ASSERT_DEVICE := d1x,d1xks` | ✅ 两个名字都对 | ROM `metadata`：`post-build=samsung/d1xks/d1x:12/SP1A.210812.016/N971NKSU2HWH5`（指纹用 `d1xks`，OTA 断言用 `d1x`） |
| `BOARD_SUPER_PARTITION_SIZE := 6480199680` | ✅ 数值有出处 | ROM `dynamic_partitions_op_list`：`add_group samsung_dynamic_partitions 6476005376`（super = 组大小 + 4 MiB 元数据） |
| `OF_DEFAULT_KEYMASTER_VERSION := 4.0` | ✅ 与 ROM 基座匹配 | 同上 `metadata` 显示 vendor 基座为 Android 12（`SP1A.210812.016`），且 `exynos9820-common.rc` 启动的就是 `android.hardware.keymaster@4.0-service.samsung` |
| `init.recovery.usb.rc` 会被加载 | ✅ 机制正确 | `bootable/recovery/etc/init.rc:4` 显式 `import /init.recovery.usb.rc`；设备树 `recovery/root/` 下的同名文件覆盖 TWRP 自带版本 |
| `exynos9820-common.rc` 的 TEE 解密流程 | ✅ 无需改 | 依次拉起 `tzdaemon` → `tzts_daemon` → `keymaster@4.0` → `gatekeeper@1.0`，并在 `twrp.decrypt.done` 后全部停止，逻辑自洽 |
| `prepdecrypt.sh` | ✅ 无需改 | 从 ROM 的 `system/build.prop`、`vendor/build.prop` 读取版本与补丁级别后 `resetprop`，符合三星 TEEgris 的校验要求 |
| VINTF manifests（system 与 vendor） | ✅ 无需改 | 声明 `keymaster@4.0` 与 `gatekeeper@1.0`，与 rc 中启动的 HAL 版本一致 |

### 唯一待真机确认的点：USB UDC 名

`init.recovery.usb.rc` 中：

```rc
setprop sys.usb.controller 10c00000.dwc3
```

- USB 控制器的 **platform 设备名**是 `10c00000.usb`（crDroid 官方 `recovery.fstab` 第 24 行：
  `/devices/platform/10c00000.usb*` 用于 `voldmanaged=usb:auto`）。
- 而 configfs 的 UDC 名由 dwc3 子设备在运行时注册，**无法离线确认**。
- 若真机上 `adb` / `MTP` 不通，优先排查这里：可在 recovery 的终端执行
  `ls /sys/class/udc/` 查看实际 UDC 名，再改成对应值。

## Credits

- [ExtremeXT](https://github.com/ExtremeXT/android_device_samsung_exynos9820) —— TWRP 设备树原型
- [LineageOS](https://github.com/LineageOS/android_device_samsung_exynos9820-common) —— 平台配置与内核

## 体积控制（recovery 分区 67,633,152 字节）

d1x 的 `recovery` 分区只有 67,633,152 字节，而 AOSP 16 + OrangeFox R12 的 ramdisk
本身就接近上限，加上 49 MB 级别的 Exynos 内核，很容易超限：

```
content 上限 = 67,633,152 - 69,632(AVB footer) = 67,563,520
content     = 2048(页) + kernel + ramdisk + dtbo(974,848)
```

超限时报错形如：

```
error: +.../recovery.img too large (68229120 > 67563520)
```

### 三个必须注意的开关语义

`bootable/recovery/prebuilt/Android.mk` 里混用了两种判断方式，**写 `false` 的后果完全不同**：

```make
# (1) false 有效
ifneq ($(filter $(PRODUCT_USE_DYNAMIC_PARTITIONS) $(TW_INCLUDE_FASTBOOTD),true),)

# (2) 非空即真 —— 写 false 等于“启用”！必须留空
ifneq ($(TW_INCLUDE_LPDUMP),)
ifneq ($(TW_INCLUDE_LPTOOLS),)
```

因此本树写成：

```make
TW_INCLUDE_REPACKTOOLS := false
TW_INCLUDE_LPDUMP :=
TW_INCLUDE_LPTOOLS :=
TW_INCLUDE_FASTBOOTD := false   # 但 PRODUCT_USE_DYNAMIC_PARTITIONS=true 时仍会带入 fastbootd
```

### `AB_OTA_UPDATER` 必须显式声明为 false

`build/make/core/board_config.mk` 在 `AB_OTA_UPDATER` 为空时会默认置 `true`，
后果有两个且都很隐蔽：

1. `bootable/recovery/orangefox.mk` 里 `FOX_AB_DEVICE := 1`，OrangeFox 会把
   **A-only 设备当 A/B 设备**处理；
2. `update_engine_sideload`（约 3.0 MB）被打进 ramdisk，本机根本用不到。

```make
AB_OTA_UPDATER := false
```

### 实测减重账

| 项目 | 未压缩 | 说明 |
| :-- | --: | :-- |
| `update_engine_sideload` + `bootctl` | 3,134,000 | `AB_OTA_UPDATER := false` 去掉 |
| `lpdump` / `lpdumpd` / `liblpdump*` / `libprotobuf-cpp-full` | 2,552,328 | `TW_INCLUDE_LPDUMP :=` 留空去掉 |
| 内核 `-O2` → `-Os` | — | 49,059,864 → 47,601,688（省 1,458,176） |
| `tzdata`（反向，必须加回来） | +407,343 | `TW_EXCLUDE_TZDATA := false` |

最终：kernel 47,601,688 + ramdisk(LZMA) 18,397,956 + dtbo 974,848 + 2048
= **66,976,540 ≤ 67,563,520**，余量 583,680 字节。

> 提示：`ramdisk-recovery.img` 的压缩命令固定为 `lzma -f -c`
> （`build/make/core/Makefile:1099`），无法在配置层调更高的压缩预设；
> `strip` 也没用 —— ramdisk 里 254 个 ELF 只有 3 个带 `.symtab`。


## 解密：boot 头部 os_version（实测结论）

`/data` 在本机使用 **元数据加密**（`metadata_encryption=aes-256-xts`，
密钥目录 `/metadata/vold/metadata_encryption`），因此**不需要用户密码**——
只要 keymaster 能解封元数据密钥，开机就会自动挂载 `/data`。

关键点：Samsung 的 keymaster 库（`libkeymaster_helper.so` /
`libkeymaster4support.so`）会读取 `ro.build.version.release` 与
`ro.build.version.security_patch`，但 TEE 侧真正用于校验的 `os_version`
来自 **boot 镜像头部**：

```
SW> keymaster (tz_init_bootloader_info:1066) os_version : 160000
SW> keymaster (swd_configure:106) invalid os_version or os_patchlevel
SW> keymaster (km_check_key_os_version_patchlevels:194) key_os_version(170000) > _os_version(160000)
I:Unable to decrypt metadata encryption
```

因此构建时必须在 `BOARD_MKBOOTIMG_ARGS` 里追加与 ROM 一致的版本：

```makefile
BOARD_MKBOOTIMG_ARGS += --os_version 17 --os_patch_level 2026-10-01
```

`prepdecrypt.sh` 另外把 `ro.system.build.*` / `ro.product.build.*` /
`ro.odm.build.*` 同步成 ROM 的值，作为二次保险。

## 手电筒：为什么用 rear_flash 而不是 LED class 节点

`/sys/class/leds/torch-sec1/brightness` 看起来更"标准"（读写一致、0~15），
但实测在本机**写进去不会点亮闪光灯**；能真正点亮的是三星私有节点
`/sys/class/camera/flash/rear_flash`，它只接受 0 / 1 / 100 / 1001~1010 /
2000~2015，且读值恒为 15。

所以 `exynos9820-common.rc` 里：

```
mkdir /dev/fox_flash 0755 root root
symlink /sys/class/camera/flash/rear_flash /dev/fox_flash/brightness
write /dev/fox_flash/max_brightness 100
```

`max_brightness` 用 init 的 `write`（带 `O_CREAT`）在 tmpfs 里生成，内容 100
= 工厂手电档 240 mA。若缺失，OrangeFox 会退化成写 `1`（60 mA，几乎看不见）。
