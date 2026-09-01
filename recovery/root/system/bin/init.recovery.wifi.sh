#!/system/bin/sh

PATH=/system/bin:/system/xbin:/vendor/bin:/sbin
export PATH

BB=/system/bin/busybox
[ -x "$BB" ] || BB=/system/bin/busybox.bin
[ -x "$BB" ] || BB=/sbin/busybox
INSMOD=/system/bin/insmod
WPA_CONF=/vendor/etc/wifi/wpa_supplicant.conf
TMP_WPA_CONF=/tmp/twrp_wpa_supplicant.conf
VENDOR_WPA_CONF=/vendor/etc/wifi/wpa_supplicant.conf
SYSTEM_WPA_CONF=/system/etc/wifi/wpa_supplicant.conf
UDHCPC_SCRIPT=/system/etc/udhcpc/default.script
UDHCPC_TMP=/tmp/twrp_udhcpc.script
UDHCPC_DEFAULT=/system/etc/udhcpc/default.script
WPA_CLI=/system/bin/wpa_cli
WPA_CLI_REAL=/system/bin/wpa_cli-real
WPA_CLI_OLD_REAL=/system/bin/wpa_cli.real
WPA_SOCKET_DIR=/data/vendor/wifi/wpa/sockets
TMP_WPA_SOCKET_DIR=/tmp/recovery/sockets
DATA_MISC_WPA_SOCKET_DIR=/data/misc/wifi/sockets
LOG_FILE=/tmp/twrp_wifi_init.log
WPA_DIRECT_PID=

WIFI_MODULES="rfkill libarc4 cfg80211 cnss_nl cnss_utils cnss_prealloc q6_pdr_dlkm snd_event_dlkm wlan_firmware_service icnss2 mac80211 qca_cld3_qca6750"
OPTIONAL_MODULES="rmnet_wlan"

log()
{
    echo "twrp_wifi: $*" > /dev/kmsg
    echo "twrp_wifi: $*" >> "$LOG_FILE"
}

one_line()
{
    echo "$*" | tr '\n' ' '
}

write_node()
{
    if [ -e "$1" ]; then
        if echo "$2" > "$1" 2>/tmp/twrp_wifi_write.err; then
            log "write $1=$2"
            return 0
        fi
        log "write $1 failed: $(one_line "$(cat /tmp/twrp_wifi_write.err 2>/dev/null)")"
    fi
    return 1
}

wait_file()
{
    path="$1"
    limit="$2"
    i=0
    while [ ! -e "$path" ] && [ "$i" -lt "$limit" ]; do
        sleep 1
        i=$((i + 1))
    done
    [ -e "$path" ]
}

module_loaded()
{
    grep -qw "^$1 " /proc/modules 2>/dev/null
}

load_module()
{
    name="$1"
    path="/vendor/lib/modules/$name.ko"

    if module_loaded "$name"; then
        log "$name already loaded"
        return 0
    fi

    if [ ! -f "$path" ]; then
        log "$path missing"
        return 1
    fi

    out=$("$INSMOD" "$path" 2>&1)
    rc=$?
    if [ "$rc" = "0" ] || module_loaded "$name"; then
        log "$name loaded"
        return 0
    fi

    log "$name insmod failed rc=$rc: $(one_line "$out")"
    return "$rc"
}

write_wpa_conf()
{
    conf="$1"
    dir="${conf%/*}"
    mkdir -p "$dir" 2>/dev/null

    if [ "$conf" = "$WPA_CONF" ] && grep -q '^network={' "$conf" 2>/dev/null; then
        chmod 0644 "$conf" 2>/dev/null
        log "kept existing $conf with configured networks"
        return 0
    fi

    tmp="$conf.tmp"
    rm -f "$tmp" 2>/dev/null
    cat > "$tmp" <<'EOF'
ctrl_interface=DIR=/data/vendor/wifi/wpa/sockets GROUP=wifi
update_config=1
eapol_version=1
ap_scan=1
fast_reauth=1
pmf=1
p2p_add_cli_chan=1
p2p_optimize_listen_chan=1
oce=1
sae_pwe=2
wowlan_disconnect_on_deinit=1
bss_no_flush_when_down=1
wowlan_triggers=magic_pkt
rsn_overriding=1
EOF
    if [ -s "$tmp" ]; then
        mv -f "$tmp" "$conf"
        chmod 0644 "$conf" 2>/dev/null
        log "wrote $conf"
    else
        rm -f "$tmp" 2>/dev/null
        if [ -s "$conf" ]; then
            chmod 0644 "$conf" 2>/dev/null
            log "kept packaged $conf"
        else
            log "failed to write $conf"
        fi
    fi
}

write_udhcpc_script()
{
    script="$1"
    dir="${script%/*}"
    mkdir -p "$dir" 2>/dev/null
    tmp="$script.tmp"
    rm -f "$tmp" 2>/dev/null
    cat > "$tmp" <<'EOF'
#!/system/bin/sh
PATH=/system/bin:/system/xbin:/vendor/bin:/sbin
export PATH

BB=/system/bin/busybox
[ -x "$BB" ] || BB=/system/bin/busybox.bin
[ -x "$BB" ] || BB=/sbin/busybox
IFACE=$interface
[ -z "$IFACE" ] && IFACE=wlan0
RESOLV=/system/etc/resolv.conf

case "$1" in
deconfig)
    "$BB" ifconfig "$IFACE" 0.0.0.0 up
    setprop dhcp.$IFACE.result failed
    ;;
bound|renew)
    NETMASK_ARG=
    BROADCAST_ARG=
    [ -n "$subnet" ] && NETMASK_ARG="netmask $subnet"
    [ -n "$broadcast" ] && BROADCAST_ARG="broadcast $broadcast"
    "$BB" ifconfig "$IFACE" "$ip" $NETMASK_ARG $BROADCAST_ARG up
    while "$BB" route del default dev "$IFACE" 2>/dev/null; do :; done
    "$BB" ip route flush cache 2>/dev/null
    FIRST_ROUTER=
    for r in $router; do
        [ -z "$FIRST_ROUTER" ] && FIRST_ROUTER=$r
        "$BB" ip route replace default via "$r" dev "$IFACE" 2>/dev/null
        "$BB" route add default gw "$r" dev "$IFACE" 2>/dev/null
        break
    done
    if [ -n "$dns" ]; then
        : > "$RESOLV"
        DNS_INDEX=1
        for ns in $dns; do
            echo "nameserver $ns" >> "$RESOLV"
            setprop net.dns$DNS_INDEX "$ns"
            [ "$DNS_INDEX" = "1" ] && setprop dhcp.$IFACE.dns1 "$ns"
            [ "$DNS_INDEX" = "2" ] && setprop dhcp.$IFACE.dns2 "$ns"
            DNS_INDEX=$((DNS_INDEX + 1))
        done
    fi
    setprop dhcp.$IFACE.ipaddress "$ip"
    setprop dhcp.$IFACE.gateway "$FIRST_ROUTER"
    setprop dhcp.$IFACE.mask "$subnet"
    setprop dhcp.$IFACE.leasetime "$lease"
    setprop dhcp.$IFACE.server "$serverid"
    setprop dhcp.$IFACE.result ok
    ;;
esac
exit 0
EOF
    if [ -s "$tmp" ]; then
        mv -f "$tmp" "$script"
        chmod 0755 "$script" 2>/dev/null
        log "wrote $script"
    else
        rm -f "$tmp" 2>/dev/null
        if [ -s "$script" ]; then
            chmod 0755 "$script" 2>/dev/null
            log "kept packaged $script"
        else
            log "failed to write $script"
        fi
    fi
}

write_dhcpcd_wrapper()
{
    path=/system/bin/dhcpcd
    tmp=/system/bin/dhcpcd.tmp
    rm -f "$tmp" 2>/dev/null
    cat > "$tmp" <<'EOF'
#!/system/bin/sh
PATH=/system/bin:/system/xbin:/vendor/bin:/sbin
export PATH

BB=/system/bin/busybox
[ -x "$BB" ] || BB=/system/bin/busybox.bin
[ -x "$BB" ] || BB=/sbin/busybox

IFACE=wlan0
KILL_ONLY=0
for arg in "$@"; do
    case "$arg" in
        -k|--release)
            KILL_ONLY=1
            ;;
        -*)
            ;;
        *)
            IFACE="$arg"
            ;;
    esac
done

PID=/tmp/udhcpc.$IFACE.pid
if [ "$KILL_ONLY" = "1" ]; then
    if [ -f "$PID" ]; then
        kill "$(cat "$PID" 2>/dev/null)" 2>/dev/null
    fi
    rm -f "$PID" 2>/dev/null
    setprop dhcp.$IFACE.result failed
    exit 0
fi

[ -x "$BB" ] || exit 1
exec "$BB" udhcpc -i "$IFACE" -s /system/etc/udhcpc/default.script -p "$PID" -t 8 -T 3 -q -n
EOF
    if [ -s "$tmp" ]; then
        rm -f "$path" 2>/dev/null
        mv -f "$tmp" "$path"
        chmod 0755 "$path" 2>/dev/null
        if [ -s "$path" ]; then
            log "wrote $path"
        else
            log "$path is empty after write"
        fi
    else
        rm -f "$tmp" 2>/dev/null
        if [ -s "$path" ]; then
            chmod 0755 "$path" 2>/dev/null
            log "kept packaged $path"
        else
            log "failed to write $path"
        fi
    fi
}

write_wpa_cli_wrapper()
{
    if [ ! -x "$WPA_CLI_REAL" ] && [ -x "$WPA_CLI_OLD_REAL" ]; then
        mv -f "$WPA_CLI_OLD_REAL" "$WPA_CLI_REAL" 2>/dev/null
        chmod 0755 "$WPA_CLI_REAL" 2>/dev/null
        log "renamed old wpa_cli.real to $WPA_CLI_REAL"
    fi

    if [ -x "$WPA_CLI" ] && ! grep -q 'TWRP_WPA_CLI_WRAPPER' "$WPA_CLI" 2>/dev/null && [ ! -x "$WPA_CLI_REAL" ]; then
        mv -f "$WPA_CLI" "$WPA_CLI_REAL" 2>/dev/null || cp -af "$WPA_CLI" "$WPA_CLI_REAL" 2>/dev/null
        chmod 0755 "$WPA_CLI_REAL" 2>/dev/null
        log "moved original wpa_cli to $WPA_CLI_REAL"
    fi

    if [ ! -x "$WPA_CLI_REAL" ]; then
        log "$WPA_CLI_REAL missing, leaving wpa_cli unwrapped"
        return 1
    fi

    tmp=/system/bin/wpa_cli.tmp
    rm -f "$tmp" 2>/dev/null
    cat > "$tmp" <<'EOF'
#!/system/bin/sh
# TWRP_WPA_CLI_WRAPPER
PATH=/sbin:/system/bin:/system/xbin:/vendor/bin
export PATH
export LD_LIBRARY_PATH=/vendor/etc/wifi/lib64:/vendor/lib64:/vendor/lib:/system/lib64:/system/lib:/sbin

REAL=/system/bin/wpa_cli-real
IFACE=wlan0
TWRP_SOCKET_DIR=/tmp/recovery/sockets
VENDOR_SOCKET_DIR=/data/vendor/wifi/wpa/sockets
DATA_MISC_SOCKET_DIR=/data/misc/wifi/sockets
HAS_P=0
HAS_I=0
CMD=

for arg in "$@"; do
    case "$arg" in
        -p|-p*)
            HAS_P=1
            ;;
        -i|-i*)
            HAS_I=1
            ;;
        -*)
            ;;
        *)
            CMD="$arg"
            break
            ;;
    esac
done

repair_socket_links()
{
    mkdir -p /tmp/recovery /data/misc/wifi /data/vendor/wifi/wpa 2>/dev/null
    if [ ! -e "$TWRP_SOCKET_DIR" ] && [ -d "$VENDOR_SOCKET_DIR" ]; then
        ln -sf "$VENDOR_SOCKET_DIR" "$TWRP_SOCKET_DIR" 2>/dev/null
    fi
    if [ ! -e "$DATA_MISC_SOCKET_DIR" ] && [ -d "$VENDOR_SOCKET_DIR" ]; then
        ln -sf "$VENDOR_SOCKET_DIR" "$DATA_MISC_SOCKET_DIR" 2>/dev/null
    fi
    chmod 0777 "$VENDOR_SOCKET_DIR" "$TWRP_SOCKET_DIR" "$DATA_MISC_SOCKET_DIR" 2>/dev/null
    chmod 0777 "$VENDOR_SOCKET_DIR/$IFACE" "$TWRP_SOCKET_DIR/$IFACE" "$DATA_MISC_SOCKET_DIR/$IFACE" 2>/dev/null
}

wait_ctrl_socket()
{
    repair_socket_links
    i=0
    while [ ! -S "$TWRP_SOCKET_DIR/$IFACE" ] && [ ! -S "$VENDOR_SOCKET_DIR/$IFACE" ] && [ "$i" -lt 20 ]; do
        sleep 1
        repair_socket_links
        i=$((i + 1))
    done
}

run_real()
{
    if [ "$HAS_P" = "1" ] && [ "$HAS_I" = "1" ]; then
        "$REAL" "$@"
    elif [ "$HAS_P" = "1" ]; then
        "$REAL" -i "$IFACE" "$@"
    elif [ "$HAS_I" = "1" ]; then
        "$REAL" -p "$TWRP_SOCKET_DIR" "$@"
    else
        "$REAL" -i "$IFACE" -p "$TWRP_SOCKET_DIR" "$@"
    fi
}

[ -x "$REAL" ] || exit 1

case "$CMD" in
    status|scan|scan_results|list_networks|add_network|set_network|enable_network|select_network|save_config|reassociate|reconnect|disconnect)
        wait_ctrl_socket
        ;;
esac

case "$CMD" in
    scan)
        out="$(run_real "$@" 2>&1)"
        rc=$?
        if echo "$out" | grep -q 'FAIL-BUSY'; then
            sleep 2
            out="$(run_real "$@" 2>&1)"
            rc=$?
        fi
        if echo "$out" | grep -q 'FAIL-BUSY'; then
            echo OK
            exit 0
        fi
        echo "$out"
        exit "$rc"
        ;;
    scan_results)
        out="$(run_real "$@" 2>&1)"
        rc=$?
        if [ "$(echo "$out" | wc -l)" -le 1 ]; then
            run_real scan >/dev/null 2>&1
            sleep 3
            out="$(run_real "$@" 2>&1)"
            rc=$?
        fi
        echo "$out"
        exit "$rc"
        ;;
    *)
        run_real "$@"
        exit "$?"
        ;;
esac
EOF
    if [ -s "$tmp" ]; then
        rm -f "$WPA_CLI" 2>/dev/null
        mv -f "$tmp" "$WPA_CLI"
        chmod 0755 "$WPA_CLI" 2>/dev/null
        ln -sf "$WPA_CLI" /sbin/wpa_cli 2>/dev/null
        rm -f /vendor/bin/wpa_cli 2>/dev/null
        ln -sf "$WPA_CLI" /vendor/bin/wpa_cli 2>/dev/null
        log "wrote wpa_cli wrapper"
    else
        rm -f "$tmp" 2>/dev/null
        if [ -x "$WPA_CLI" ]; then
            log "kept packaged wpa_cli wrapper"
        else
            log "failed to write wpa_cli wrapper"
        fi
    fi
}

write_runtime_files()
{
    chmod 0755 "$BB" "$INSMOD" 2>/dev/null
    rm -f /system/bin/ip /system/bin/route /system/bin/udhcpc /system/bin/ping /system/bin/ifconfig /system/bin/netstat
    ln -sf "$BB" /system/bin/ip
    ln -sf "$BB" /system/bin/route
    ln -sf "$BB" /system/bin/udhcpc
    ln -sf "$BB" /system/bin/ping
    ln -sf "$BB" /system/bin/ifconfig
    ln -sf "$BB" /system/bin/netstat
    ln -sf "$BB" /sbin/ip 2>/dev/null
    ln -sf "$BB" /sbin/route 2>/dev/null
    ln -sf "$BB" /sbin/udhcpc 2>/dev/null
    ln -sf "$BB" /sbin/ping 2>/dev/null
    ln -sf "$BB" /sbin/ifconfig 2>/dev/null
    ln -sf "$BB" /sbin/netstat 2>/dev/null

    chown root:wifi /tmp 2>/dev/null
    chmod 0775 /tmp 2>/dev/null
    mkdir -p /tmp/recovery /data/misc/wifi /data/vendor/wifi/wpa
    [ -L "$WPA_SOCKET_DIR" ] && rm -f "$WPA_SOCKET_DIR"
    mkdir -p "$WPA_SOCKET_DIR"
    chown wifi:wifi /data/vendor/wifi /data/vendor/wifi/wpa "$WPA_SOCKET_DIR" 2>/dev/null
    chmod 0775 /data/vendor/wifi /data/vendor/wifi/wpa 2>/dev/null
    chmod 0777 /tmp/recovery "$WPA_SOCKET_DIR" 2>/dev/null
    rm -rf "$TMP_WPA_SOCKET_DIR" "$DATA_MISC_WPA_SOCKET_DIR"
    ln -sf "$WPA_SOCKET_DIR" "$TMP_WPA_SOCKET_DIR"
    ln -sf "$WPA_SOCKET_DIR" "$DATA_MISC_WPA_SOCKET_DIR"
    chmod 0777 "$TMP_WPA_SOCKET_DIR" "$DATA_MISC_WPA_SOCKET_DIR" 2>/dev/null

    mkdir -p /data/vendor/firmware/update/wlan
    chown system:system /data/misc /data/vendor /data/vendor/firmware /data/vendor/firmware/update /data/vendor/firmware/update/wlan 2>/dev/null
    chown wifi:wifi /data/misc/wifi 2>/dev/null
    chmod 0771 /data/misc /data/misc/wifi /data/vendor /data/vendor/firmware /data/vendor/firmware/update /data/vendor/firmware/update/wlan 2>/dev/null

    write_wpa_conf "$WPA_CONF"
    write_wpa_conf "$SYSTEM_WPA_CONF"
    chmod 0644 "$WPA_CONF" "$SYSTEM_WPA_CONF" 2>/dev/null
    rm -f "$TMP_WPA_CONF" 2>/dev/null
    ln -sf "$WPA_CONF" "$TMP_WPA_CONF" 2>/dev/null

    write_udhcpc_script "$UDHCPC_SCRIPT"
    rm -f "$UDHCPC_TMP" 2>/dev/null
    ln -sf "$UDHCPC_SCRIPT" "$UDHCPC_TMP" 2>/dev/null
    write_dhcpcd_wrapper
    write_wpa_cli_wrapper

    setprop wifi.interface wlan0
    setprop wlan.driver.status ok
}

poke_wpss()
{
    write_node /proc/sys/kernel/firmware_config/force_sysfs_fallback 1
    write_node /sys/kernel/icnss/wlan_en_delay 1000
    write_node /sys/kernel/icnss/wpss_boot 1
    write_node /sys/devices/platform/soc/17110040.qcom,wcn6750/wlan_en_delay 1000
    write_node /sys/devices/platform/soc/17110040.qcom,wcn6750/wpss_boot 1

    if [ -e /sys/class/remoteproc/remoteproc0/state ]; then
        state=$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)
        if [ "$state" = "offline" ]; then
            echo start > /sys/class/remoteproc/remoteproc0/state 2>/dev/null
        fi
        log "remoteproc0 state $(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)"
    fi
}

load_wifi_stack()
{
    for mod in $WIFI_MODULES; do
        load_module "$mod"
        [ "$mod" = "icnss2" ] && poke_wpss
    done

    for mod in $OPTIONAL_MODULES; do
        load_module "$mod" || log "$mod optional, continuing"
    done
}

wait_wlan0()
{
    limit="$1"
    i=0
    while [ ! -e /sys/class/net/wlan0 ] && [ "$i" -lt "$limit" ]; do
        sleep 1
        i=$((i + 1))
    done
    [ -e /sys/class/net/wlan0 ]
}

kill_wpa_supplicant()
{
    "$BB" killall wpa_supplicant 2>/dev/null
    pids="$("$BB" pidof wpa_supplicant 2>/dev/null) $(pidof wpa_supplicant 2>/dev/null)"
    for pid in $pids; do
        kill "$pid" 2>/dev/null
    done
    sleep 1
    for pid in $pids; do
        [ -d "/proc/$pid" ] && kill -9 "$pid" 2>/dev/null
    done
}

reset_dhcp_state()
{
    [ -e /sys/class/net/wlan0 ] || return 0
    while "$BB" route del default dev wlan0 2>/dev/null; do :; done
    "$BB" ip route flush cache 2>/dev/null
    "$BB" ifconfig wlan0 0.0.0.0 up 2>/dev/null
    setprop dhcp.wlan0.ipaddress ""
    setprop dhcp.wlan0.gateway ""
    setprop dhcp.wlan0.dns1 ""
    setprop dhcp.wlan0.dns2 ""
    setprop dhcp.wlan0.result failed
}

start_wpa_direct()
{
    WPA_BIN=/vendor/bin/wpa_supplicant
    [ -x "$WPA_BIN" ] || WPA_BIN=/system/bin/wpa_supplicant

    if [ ! -x "$WPA_BIN" ]; then
        log "wpa_supplicant binary missing"
        return 1
    fi

    export LD_LIBRARY_PATH=/vendor/etc/wifi/lib64:/vendor/lib64:/vendor/lib:/system/lib64:/system/lib:/sbin
    "$WPA_BIN" -Dnl80211 -iwlan0 -c"$WPA_CONF" -O"$WPA_SOCKET_DIR" >/tmp/twrp_wpa_supplicant.log 2>&1 &
    WPA_DIRECT_PID=$!
    log "wpa_supplicant started directly via $WPA_BIN pid $WPA_DIRECT_PID"
    return 0
}

start_wpa_service()
{
    kill_wpa_supplicant
    reset_dhcp_state
    rm -f "$WPA_SOCKET_DIR"/wlan0 "$WPA_SOCKET_DIR"/p2p0 "$WPA_SOCKET_DIR"/wpa_ctrl_* "$TMP_WPA_SOCKET_DIR"/wpa_ctrl_* "$DATA_MISC_WPA_SOCKET_DIR"/wpa_ctrl_* 2>/dev/null
    setprop twrp.wifi.driver.ready false
    setprop ctl.stop wpa_supplicant
    sleep 1
    setprop twrp.wifi.driver.ready true
    log "requested init wpa_supplicant service"

    i=0
    while [ ! -S "$WPA_SOCKET_DIR/wlan0" ] && [ "$i" -lt 12 ]; do
        sleep 1
        i=$((i + 1))
    done

    if [ ! -S "$WPA_SOCKET_DIR/wlan0" ]; then
        log "init wpa_supplicant service did not create socket, using direct fallback"
        start_wpa_direct
    fi

    i=0
    while [ ! -S "$WPA_SOCKET_DIR/wlan0" ] && [ "$i" -lt 20 ]; do
        sleep 1
        i=$((i + 1))
    done
    chmod 0777 /tmp/recovery "$WPA_SOCKET_DIR" "$TMP_WPA_SOCKET_DIR" "$DATA_MISC_WPA_SOCKET_DIR" 2>/dev/null
    chmod 0777 "$WPA_SOCKET_DIR/wlan0" 2>/dev/null
    chmod 0777 "$TMP_WPA_SOCKET_DIR/wlan0" "$DATA_MISC_WPA_SOCKET_DIR/wlan0" 2>/dev/null
    ls -l "$WPA_SOCKET_DIR/wlan0" >> "$LOG_FILE" 2>/dev/null
}

runtime_files_ready()
{
    [ -s "$WPA_CONF" ] || return 1
    [ -s "$UDHCPC_SCRIPT" ] || return 1
    [ -s /system/bin/dhcpcd ] || return 1
    [ -x "$WPA_CLI_REAL" ] || return 1
    [ -x "$WPA_CLI" ] || return 1
    return 0
}

prepare_runtime_files()
{
    runtime_attempt=1
    while [ "$runtime_attempt" -le 6 ]; do
        mkdir -p /tmp /tmp/recovery /data/misc/wifi /data/vendor/wifi/wpa /system/etc/udhcpc 2>/dev/null
        chmod 0777 /tmp 2>/dev/null
        write_runtime_files
        if runtime_files_ready; then
            log "runtime files ready"
            return 0
        fi
        log "runtime files incomplete after attempt $runtime_attempt, retrying"
        sleep 2
        runtime_attempt=$((runtime_attempt + 1))
    done

    log "runtime files still incomplete, continuing with packaged files"
    return 1
}

log "script start"

# Start immediately on early-boot; the retry loop below handles firmware/vendor readiness.

attempt=1
while [ "$attempt" -le 3 ] && [ ! -e /sys/class/net/wlan0 ]; do
    log "driver attempt $attempt"
    wait_file /vendor/lib/modules/qca_cld3_qca6750.ko 30 || log "qca_cld3_qca6750.ko still missing"
    poke_wpss
    load_wifi_stack
    poke_wpss
    wait_wlan0 45 && break
    log "wlan0 missing after attempt $attempt"
    attempt=$((attempt + 1))
    sleep 5
done

if [ ! -e /sys/class/net/wlan0 ]; then
    setprop twrp.wifi.driver.ready false
    log "wlan0 missing after retries"
    exit 0
fi

/system/bin/ifconfig wlan0 up 2>/dev/null || "$BB" ifconfig wlan0 up 2>/dev/null
log "wlan0 up"

# Rootfs setup can still be changing during early-boot. Generate the runtime
# wrappers after the driver is ready, when the target directories are stable.
prepare_runtime_files

start_wpa_service
if [ -n "$WPA_DIRECT_PID" ]; then
    log "script staying alive for direct wpa_supplicant pid $WPA_DIRECT_PID"
    wait "$WPA_DIRECT_PID"
    log "direct wpa_supplicant exited"
else
    log "script done"
fi
