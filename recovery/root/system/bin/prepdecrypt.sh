#!/system/bin/sh
#
# Prepare /data decryption with the installed ROM: report its OS version and
# security patch levels to the keymaster, and stage its TEEgris daemons and
# gatekeeper modules. The keymaster must not start with mismatching values.
#

system_mnt=/tmp/prepdecrypt/system

fail() {
    umount "$system_mnt" 2>/dev/null
    umount /vendor_rom 2>/dev/null
    setprop prepdecrypt.status failed
    exit 1
}

mount_logical() {
    mkdir -p "$2"
    mount -t erofs -o ro "/dev/block/mapper/$1" "$2" 2>/dev/null ||
        mount -t ext4 -o ro "/dev/block/mapper/$1" "$2"
}

get_prop() {
    grep -m 1 "^$1=" "$2" | cut -d '=' -f 2-
}

mount_logical vendor /vendor_rom || fail
mount_logical system "$system_mnt" || fail

os_version=$(get_prop ro.build.version.release "$system_mnt/system/build.prop")
os_patch=$(get_prop ro.build.version.security_patch "$system_mnt/system/build.prop")
vendor_patch=$(get_prop ro.vendor.build.security_patch /vendor_rom/build.prop)
umount "$system_mnt"

[ -n "$os_version" ] && [ -n "$os_patch" ] && [ -n "$vendor_patch" ] || fail

resetprop ro.build.version.release "$os_version" || fail
resetprop ro.build.version.security_patch "$os_patch" || fail
resetprop ro.vendor.build.security_patch "$vendor_patch" || fail

# Samsung keymaster 会比对密钥里记录的 os_version/patchlevel 与当前系统的值，
# 密钥版本高于系统会被拒绝解封（/metadata 的元数据密钥就是这样拿不到的）。
# boot 头部的 os_version 走 BoardConfig 的 BOARD_MKBOOTIMG_ARGS；
# patchlevel 与其余维度由这里的属性提供。
resetprop ro.system.build.version.release "$os_version" || fail
resetprop ro.system.build.version.security_patch "$os_patch" || fail
resetprop ro.product.build.version.release "$os_version" || fail
resetprop ro.product.build.version.security_patch "$os_patch" || fail
resetprop ro.odm.build.version.release "$os_version" || fail
resetprop ro.odm.build.version.security_patch "$os_patch" || fail

grep -q " /efs " /proc/mounts ||
    mount -t ext4 -o nosuid,nodev,noatime /dev/block/by-name/efs /efs || fail
mkdir -p /mnt/vendor
ln -sf /efs /mnt/vendor/efs

mkdir -p /vendor/bin /vendor/lib64/hw
cp /vendor_rom/bin/tzdaemon /vendor_rom/bin/tzts_daemon /vendor/bin/ || fail
chmod 0755 /vendor/bin/tzdaemon /vendor/bin/tzts_daemon
cp /vendor_rom/lib64/hw/android.hardware.gatekeeper@1.0-impl.so \
    /vendor_rom/lib64/hw/gatekeeper.*.so /vendor/lib64/hw/ || fail

setprop prepdecrypt.status done
