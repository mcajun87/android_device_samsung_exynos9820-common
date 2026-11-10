#!/system/bin/sh
#
# 禁止 ROM 把官方 recovery 写回去（OrangeFox d1x 默认启用）
#
# 原理：AOSP 系的 ROM 在开机时由 install-recovery.sh 应用
#       /system/recovery-from-boot.p，把 recovery 分区恢复成官方镜像。
#       本脚本在 recovery 启动时把这两样东西改名，从而让它失效；
#       同时处理 /vendor 下的同名文件与 init 服务定义。
#
# 安全性：
#   - 只改名（.ofdis 后缀），不删除，随时可恢复
#   - 已处理过会留下标记，避免重复操作
#   - 任何一步失败都只记录日志，不中断 recovery
#
LOG=/tmp/disablestockrecovery.log
echo "[$(date)] 开始" > "$LOG"

# 等 ROM 的 system 挂载（TWRP 会挂到 /system_root）
i=0
while [ $i -lt 60 ]; do
    for d in /system_root/system /system/system /system_root /system; do
        if [ -e "$d/recovery-from-boot.p" ] || [ -e "$d/bin/install-recovery.sh" ] || [ -e "$d/etc/install-recovery.sh" ]; then
            SYSROOT="$d"
            break
        fi
    done
    [ -n "${SYSROOT:-}" ] && break
    i=$((i+1))
    sleep 1
done

if [ -z "${SYSROOT:-}" ]; then
    echo "[$(date)] 没有找到 recovery-from-boot 相关文件，ROM 可能本身不带该机制" >> "$LOG"
    exit 0
fi
echo "[$(date)] 目标目录: $SYSROOT" >> "$LOG"

REM=""
for x in system vendor product system_ext; do
    [ -d "/$x" ] && REM="mount -o remount,rw /$x"
done

remount_rw() {
    mount -o remount,rw / 2>/dev/null
    mount -o remount,rw "$1" 2>/dev/null
    mount -o remount,rw /system_root 2>/dev/null
}
remount_ro() {
    mount -o remount,ro / 2>/dev/null
    mount -o remount,ro "$1" 2>/dev/null
    mount -o remount,ro /system_root 2>/dev/null
}

dis() {
    f="$1"
    [ -e "$f" ] || return 0
    [ -e "$f.ofdis" ] && { echo "[$(date)] 已处理: $f" >> "$LOG"; return 0; }
    if mv "$f" "$f.ofdis" 2>>"$LOG"; then
        echo "[$(date)] 改名成功: $f -> $f.ofdis" >> "$LOG"
    else
        echo "[$(date)] 改名失败: $f" >> "$LOG"
    fi
}

PARENT=$(dirname "$SYSROOT")
remount_rw "$PARENT"
dis "$SYSROOT/recovery-from-boot.p"
dis "$SYSROOT/bin/install-recovery.sh"
dis "$SYSROOT/etc/install-recovery.sh"
dis "$SYSROOT/recovery-resource.dat"
dis "$SYSROOT/etc/recovery-resource.dat"
# init 里的 flash_recovery 服务定义
for f in "$SYSROOT/etc/init/flash_recovery.rc" "$SYSROOT/etc/init/install-recovery.rc"; do
    [ -e "$f" ] && dis "$f"
done
remount_ro "$PARENT"

echo "[$(date)] 完成" >> "$LOG"
exit 0
