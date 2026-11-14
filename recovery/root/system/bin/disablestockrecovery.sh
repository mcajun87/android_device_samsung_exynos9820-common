#!/system/bin/sh
#
# 阻止 ROM 把官方 recovery 写回去（OrangeFox d1x 默认启用）
#
# 真凶不是 AOSP 的 install-recovery.sh，而是三星系的 recovery-persist：
#   /system/bin/recovery-persist   在系统启动时把 recovery 分区覆盖回官方镜像
# 本脚本把该二进制与其 init 服务改名（.ofdis），使它无法执行。
#
# 另外仍会顺带处理 AOSP 的 recovery-from-boot.p / install-recovery.sh，
# 以防 ROM 版本不同。
#
# 安全策略：
#   - 只改名，不删除，随时可改回
#   - 必须先把 ROM 的 system 挂上（TWRP 通常挂到 /system_root；没挂就自己挂）
#   - 任何失败只写日志，不影响 recovery 启动
#
LOG=/tmp/disablestockrecovery.log
say() { echo "[$(date)] $*" >> "$LOG"; }
echo "[$(date)] 开始" > "$LOG"

SYSDEV=/dev/block/mapper/system
[ -e "$SYSDEV" ] || SYSDEV=$(readlink -f /dev/block/by-name/system 2>/dev/null)

# ---------- 1. 等 / 或自己挂载 system ----------
SR=""
i=0
while [ $i -lt 120 ]; do
    if mount | grep -q ' /system_root '; then SR=/system_root; break; fi
    if [ -e /system_root/bin/recovery-persist ]; then SR=/system_root; break; fi
    i=$((i+1)); sleep 1
done

MOUNTED_BY_US=0
if [ -z "$SR" ]; then
    say "TWRP 未挂载 system，自己挂"
    mkdir -p /system_root
    if mount -t ext4 -o rw "$SYSDEV" /system_root 2>>"$LOG"; then
        SR=/system_root; MOUNTED_BY_US=1
        say "自挂成功: $SYSDEV -> /system_root"
    elif mount -t erofs -o rw "$SYSDEV" /system_root 2>>"$LOG"; then
        SR=/system_root; MOUNTED_BY_US=1
        say "自挂成功(erofs): $SYSDEV"
    else
        say "挂载失败，放弃"
        exit 0
    fi
fi
say "system 根: $SR"

# ---------- 2. 改成可写 ----------
mount -o remount,rw /system_root 2>>"$LOG"
if ! touch "$SR/.of_wtest" 2>/dev/null; then
    say "system 分区不可写（可能是 dm-verity/只读），尝试用 /system 路径"
    SR=/system
fi
rm -f "$SR/.of_wtest" 2>/dev/null

# ---------- 3. 逐个改名 ----------
dis() {
    f="$1"
    [ -e "$f" ] || return 0
    [ -e "$f.ofdis" ] && { say "已处理: $f"; return 0; }
    if mv "$f" "$f.ofdis" 2>>"$LOG"; then
        say "改名成功: $f"
    else
        say "改名失败: $f"
    fi
}

# 真凶：recovery-persist
dis "$SR/bin/recovery-persist"
dis "$SR/system/bin/recovery-persist"
dis "$SR/etc/init/recovery-persist.rc"
dis "$SR/system/etc/init/recovery-persist.rc"
dis "$SR/etc/recovery-persist"
dis "$SR/system/etc/recovery-persist"

# AOSP 传统机制（若无则自动跳过）
dis "$SR/recovery-from-boot.p"
dis "$SR/system/recovery-from-boot.p"
dis "$SR/bin/install-recovery.sh"
dis "$SR/system/bin/install-recovery.sh"
dis "$SR/etc/install-recovery.sh"
dis "$SR/system/etc/install-recovery.sh"

# ---------- 4. 收尾 ----------
if [ "$MOUNTED_BY_US" = "1" ]; then
    umount /system_root 2>/dev/null
    say "已卸载 /system_root"
else
    mount -o remount,ro /system_root 2>/dev/null
    say "已恢复只读"
fi
say "完成"
exit 0
