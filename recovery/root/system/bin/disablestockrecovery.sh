#!/system/bin/sh
#
# 防止 ROM 把官方 recovery 镜像写回去（OrangeFox d1x 默认开启）
# ---------------------------------------------------------------------------
# 真实机制（2026-11 在 Evolution X A17 / d1x 实机上查证，不是猜的）：
#
#   1) /vendor/etc/recovery.img
#        完整的三星官方 recovery 镜像，67633152 字节，正好等于 recovery 分区大小。
#        这是"原版镜像"的唯一来源。
#   2) /vendor/etc/init/vendor_flash_recovery.rc
#        service vendor_flash_recovery /vendor/bin/install-recovery.sh
#        on property:persist.vendor.recovery_update=true  ->  start
#        即：只要这个 persist 属性被置成 true，系统启动时就会把
#        /vendor/etc/recovery.img 写回 recovery 分区。
#   3) /vendor/recovery-from-boot.p + /vendor/bin/install-recovery.sh
#        OneUI/部分机型的等价形式（用 applypatch 增量数据还原）。
#
#   注意：/system/bin/recovery-persist **不是**元凶。它是 AOSP 原生的
#   pmsg 日志轮转（bootable/recovery/recovery-persist.cpp），只往
#   /data/misc/recovery 写 last_log/last_kmsg，绝不碰 recovery 分区。
#
# 处理策略分两级，先做绝对安全的一级：
#
#   A. 清掉 persist.vendor.recovery_update（永远执行，绝对安全）
#      persist 属性存在 /persistent/properties/ 下，persistent 分区没有
#      dm-verity 保护，改它不会影响开机。清掉后 vendor_flash_recovery
#      服务永远不会被拉起。
#
#   B. 把 /vendor 下的还原来源改名（有条件执行）
#      /vendor 和 /system 在 verity 模式为 enforcing 时是不可改的：
#      改了会让 dm-verity 校验失败，机器直接开不了机。所以只有确认
#      verity 未强制时才做。判断依据：/proc/cmdline 里的
#      androidboot.veritymode。
#      自建的 Evolution X ROM 的 proprietary-files.txt 里本来就没有
#      recovery.img / vendor_flash_recovery.rc，所以这一步对自建 ROM
#      是空操作，专用于第三方预编译 ROM。
#
# 安全约定：
#   - 全部只改名（.ofdis 后缀），不删除，随时能改回来
#   - 任何一步失败只写日志，不中断 recovery 启动
#   - 有强制开关，见下面 opt-out / force 说明
# ---------------------------------------------------------------------------
# 关闭本功能：  touch /tmp/no_stock_recovery_restore      （本次启动生效）
# 强制执行 B：  touch /tmp/force_stock_recovery_block     （明知 verity 关着时）
#
LOG=/tmp/disablestockrecovery.log
say() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
echo "[$(date)] 开始" > "$LOG"

# ---------- opt-out ----------
if [ -e /tmp/no_stock_recovery_restore ]; then
    say "存在 /tmp/no_stock_recovery_restore，跳过"
    exit 0
fi

# 不能和 decryption 抢 /vendor：预解密流程要求 /vendor 未挂载
i=0
while [ "$i" -lt 60 ]; do
    if [ -z "$(getprop dev.mnt.blk.vendor)" ]; then break; fi
    i=$((i+1)); sleep 1
done
say "dev.mnt.blk.vendor=[$(getprop dev.mnt.blk.vendor)] 等待 ${i}s"

# ===========================================================================
# A. 清掉 persist.vendor.recovery_update（安全，永远执行）
# ===========================================================================
PDEV=""
for c in /dev/block/by-name/persistent /dev/block/mapper/persistent /dev/block/sda19; do
    [ -e "$c" ] && { PDEV="$c"; break; }
done

if [ -z "$PDEV" ]; then
    say "A: 找不到 persistent 分区，跳过"
else
    P=/tmp/of_persist
    mkdir -p "$P"
    if mount -o rw "$PDEV" "$P" 2>>"$LOG"; then
        found=0
        for f in "$P/properties/persist.vendor.recovery_update" \
                 "$P/properties/persist.vendor.recovery_update.true" \
                 "$P/prop/persist.vendor.recovery_update"; do
            if [ -e "$f" ]; then
                found=1
                cur=$(cat "$f" 2>/dev/null)
                say "A: 发现 $f = [$cur]"
                if [ -e "$f.ofdis" ]; then rm -f "$f.ofdis"; fi
                if mv "$f" "$f.ofdis" 2>>"$LOG"; then
                    say "A: 已改名 -> .ofdis（该服务将无法被触发）"
                else
                    say "A: 改名失败"
                fi
            fi
        done
        [ "$found" = "0" ] && say "A: 没有 persist.vendor.recovery_update（服务本来就不会启动）"
        umount "$P" 2>/dev/null
    else
        say "A: 挂载 persistent 失败，跳过"
    fi
    rmdir "$P" 2>/dev/null
fi

# ===========================================================================
# B. 改掉 /vendor、/system 下的还原来源（只在 verity 未强制时）
# ===========================================================================
CMDLINE=$(cat /proc/cmdline 2>/dev/null)
VERITY=$(echo "$CMDLINE" | tr ' ' '\n' | sed -n 's/^androidboot\.veritymode=//p')
[ -z "$VERITY" ] && VERITY=$(getprop ro.boot.veritymode)
say "B: androidboot.veritymode=[$VERITY]"

DO_B=0
case "$VERITY" in
    enforcing)
        if [ -e /tmp/force_stock_recovery_block ]; then
            DO_B=1; say "B: verity=enforcing，但存在 force 标记，仍然执行"
        else
            say "B: verity=enforcing —— 改动会被 dm-verity 判定为损坏、导致无法开机，跳过"
            say "B: 若确认本机 verity 实际已关闭，可 touch /tmp/force_stock_recovery_block 后重试"
        fi
        ;;
    *)
        DO_B=1
        say "B: verity 未强制（[$VERITY]），执行改名"
        ;;
esac

dis() {
    f="$1"
    [ -e "$f" ] || return 0
    if [ -e "$f.ofdis" ]; then say "  已处理过: $f"; return 0; fi
    if mv "$f" "$f.ofdis" 2>>"$LOG"; then
        say "  改名成功: $f"
    else
        say "  改名失败: $f"
    fi
}

neutralise_part() {
    local name="$1" dev="$2"
    [ -e "$dev" ] || { say "  $name: 设备不存在 $dev"; return 0; }
    local M=/tmp/of_$name
    mkdir -p "$M"
    blockdev --setrw "$dev" 2>/dev/null
    if ! mount -o rw "$dev" "$M" 2>>"$LOG"; then
        say "  $name: 挂载失败，跳过"
        rmdir "$M" 2>/dev/null
        blockdev --setro "$dev" 2>/dev/null
        return 0
    fi
    say "  $name: 已挂载到 $M（可写）"
    # 三星系
    dis "$M/etc/recovery.img"
    dis "$M/bin/install-recovery.sh"
    dis "$M/etc/init/vendor_flash_recovery.rc"
    dis "$M/recovery-from-boot.p"
    # AOSP 系
    dis "$M/etc/install-recovery.sh"
    dis "$M/etc/init/install-recovery.rc"
    dis "$M/recovery-resource.dat"
    dis "$M/etc/recovery-resource.dat"
    sync
    umount "$M" 2>/dev/null
    rmdir "$M" 2>/dev/null
    blockdev --setro "$dev" 2>/dev/null
    say "  $name: 已卸载并恢复只读"
}

if [ "$DO_B" = "1" ]; then
    # /system 本体在 system 分区，recovery 视角下可能已挂在 /system_root
    if mount | grep -q ' /system_root '; then
        say "B: system 已由 TWRP 挂在 /system_root，就地处理"
        dis /system_root/bin/install-recovery.sh
        dis /system_root/etc/install-recovery.sh
        dis /system_root/recovery-from-boot.p
        dis /system_root/etc/init/install-recovery.rc
    else
        neutralise_part system /dev/block/mapper/system
    fi
    neutralise_part vendor /dev/block/mapper/vendor
else
    say "B: 跳过（见上面的 verity 判断）"
fi

say "完成"
exit 0
