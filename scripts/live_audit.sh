#!/bin/bash
# live_audit.sh — Dynamic runtime metrics collected immediately after benchmark.
# Captures load-induced state: socket churn, NIC drops, softirq saturation, CPU pressure.
# Run on DUT right after benchmark completes — kernel counters persist for seconds.

fmt_line() { printf "  %-38s | %-40s\n" "$1" "$2"; }

NIC_DEV=$(ip -o -4 route show to default | awk '{print $5}')
NGINX_PID=$(pgrep -n nginx)

# --- [L1] TCP Socket State ---
echo "[L1] TCP Socket State (ss -s)"
ss -s 2>/dev/null | while IFS= read -r line; do
    fmt_line "ss_summary" "$line"
done

# --- [L2] Per-CPU Softnet (network backlog / softirq pressure) ---
echo ""
echo "[L2] Softnet Counters (/proc/net/softnet_stat)"
TOTAL_SQUEEZED=$(awk '{sum+=strtonum("0x"$3)} END {printf "%d", sum}' /proc/net/softnet_stat)
TOTAL_DROPPED=$(awk '{sum+=strtonum("0x"$2)} END {printf "%d", sum}' /proc/net/softnet_stat)
fmt_line "Softnet_Total_Dropped"   "$TOTAL_DROPPED"
fmt_line "Softnet_Total_Squeezed"  "$TOTAL_SQUEEZED"

# --- [L3] NIC Driver Counters (ring-level drops) ---
echo ""
echo "[L3] NIC Driver Counters (ethtool -S)"
if ethtool -S "$NIC_DEV" 2>/dev/null | grep -qiE 'discard|drop|error|miss'; then
    ethtool -S "$NIC_DEV" 2>/dev/null | grep -iE 'discard|drop|error|miss' | \
        grep -v ': 0$' | head -20 | while IFS=: read -r key val; do
        fmt_line "NIC_${key// /_}" "$(echo "$val" | xargs)"
    done
else
    fmt_line "NIC_Errors" "none detected"
fi

# --- [L4] Kernel Socket Memory (/proc/net/sockstat) ---
echo ""
echo "[L4] Socket Memory Snapshot (/proc/net/sockstat)"
grep -E '^(TCP|UDP|FRAG)' /proc/net/sockstat 2>/dev/null | while IFS= read -r line; do
    fmt_line "sockstat" "$line"
done

# --- [L5] CPU Activity Snapshot (vmstat) ---
echo ""
echo "[L5] CPU Activity (vmstat 1 3)"
vmstat 1 3 2>/dev/null | tail -1 | awk '{
    printf "  %-38s | %-40s\n", "vmstat_us_sy_id_wa", $13"/"$14"/"$15"/"$16
    printf "  %-38s | %-40s\n", "vmstat_in_cs", $11"/"$12
}'

# --- [L6] Cgroup CPU Throttling (nginx service) ---
echo ""
echo "[L6] Cgroup CPU Throttle (nginx.service)"
CGROUP_PATH=$(cat /proc/"$NGINX_PID"/cgroup 2>/dev/null | grep -E 'cpu$|cpuacct' | head -1 | cut -d: -f3)
CPU_STAT="/sys/fs/cgroup/cpu${CGROUP_PATH}/cpu.stat"
if [[ -f "$CPU_STAT" ]]; then
    NR_THROTTLED=$(grep nr_throttled "$CPU_STAT" | awk '{print $2}')
    THROTTLED_US=$(grep throttled_usec "$CPU_STAT" 2>/dev/null | awk '{print $2}')
    NR_PERIODS=$(grep nr_periods "$CPU_STAT" | awk '{print $2}')
    THROTTLE_RATIO=0
    [[ "$NR_PERIODS" -gt 0 ]] && THROTTLE_RATIO=$(awk "BEGIN {printf \"%.2f\", ($NR_THROTTLED/$NR_PERIODS)*100}")
    fmt_line "Cgroup_NR_Throttled"   "${NR_THROTTLED:-N/A}"
    fmt_line "Cgroup_Throttled_usec" "${THROTTLED_US:-N/A}"
    fmt_line "Cgroup_NR_Periods"     "${NR_PERIODS:-N/A}"
    fmt_line "Cgroup_Throttle_Ratio" "${THROTTLE_RATIO}%"
else
    fmt_line "Cgroup_CPU_Stat" "not found at $CPU_STAT"
fi

echo ""
echo "================ Live Audit Complete ===================="
