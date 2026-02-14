#!/bin/bash

# --- Colors ---
NONE='\033[0m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'

# --- Labels ---
L_TITLE="System Real-time Monitor"
L_CORE="[Core Info]"
L_RES="[Resource Usage]"
L_DISK="[Disk Status]"
L_CPU="CPU Model"
L_IPV4="IPv4 Addr"
L_IPV6="IPv6 Addr"
L_UPTIME="Uptime"
L_LOAD="CPU Load"
L_PROCS="Processes"
L_MEM="Memory"
L_USERS="Users Logged"
L_SWAP="Swap Usage"
L_NET="Network Speed"
L_UPLOAD="Upload"
L_DOWNLOAD="Download"
L_MNT="Mount"
L_SIZE="Size"
L_USED="Used"
L_PERC="Perm"
L_PROG="Progress"

# --- Progress Bar Function ---
draw_bar() {
    local perc=$1
    local max_len=$2
    local fill_len=$(( perc * max_len / 100 ))
    local empty_len=$(( max_len - fill_len ))
    local color=$GREEN

    if [ "$perc" -ge 90 ]; then
        color=$RED
    elif [ "$perc" -ge 70 ]; then
        color=$YELLOW
    fi

    printf "${color}"
    for ((i=0; i<fill_len; i++)); do printf "■"; done
    printf "${NONE}"
    for ((i=0; i<empty_len; i++)); do printf " "; done
}

# --- Data Collection ---
# Get CPU usage using uptime/load average (simplest and most reliable)
LOAD_AVG=$(cat /proc/loadavg 2>/dev/null | tr -d '\r' | awk '{print $1}' || echo "0")
# Validate LOAD_AVG is numeric
if ! [[ "$LOAD_AVG" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    LOAD_AVG="0"
fi
CPU_CORES=$(nproc 2>/dev/null | tr -d '\r' || echo "1")
# Validate CPU_CORES is numeric
if ! [[ "$CPU_CORES" =~ ^[0-9]+$ ]]; then
    CPU_CORES="1"
fi
# Calculate CPU usage - use bc if available, otherwise use awk
if command -v bc >/dev/null 2>&1; then
    CPU_USAGE_NUM=$(echo "scale=1; $LOAD_AVG * 100 / $CPU_CORES" | bc -l | tr -d '\r' || echo "0")
else
    CPU_USAGE_NUM=$(awk "BEGIN {printf \"%.1f\", $LOAD_AVG * 100 / $CPU_CORES}" | tr -d '\r' || echo "0")
fi
CPU_USAGE=$(printf "%.1f%%" "$CPU_USAGE_NUM")
PROCESSES=$(ps ax 2>/dev/null | wc -l | tr -d ' ' || echo "0")
USERS_LOGGED=$(who 2>/dev/null | wc -l || echo "0")
MEM_TOTAL=$(free -h 2>/dev/null | awk 'NR==2{print $2}' || echo "N/A")
MEM_USED=$(free -h 2>/dev/null | awk 'NR==2{print $3}' || echo "N/A")
MEM_PERC_NUM=$(free -m 2>/dev/null | awk 'NR==2{printf "%d", $3*100/$2}' || echo "0")
MEM_INFO="$MEM_USED / $MEM_TOTAL ($MEM_PERC_NUM%)"
SWAP_TOTAL_M=$(free -m 2>/dev/null | awk 'NR==3{print $2}' || echo "0")
if [ "$SWAP_TOTAL_M" -gt 0 ]; then
    SWAP_PERC_NUM=$(free -m 2>/dev/null | awk 'NR==3{printf "%d", $3*100/$2}' || echo "0")
    SWAP_USAGE="${SWAP_PERC_NUM}%"
else
    SWAP_USAGE="None"
fi
IP_V4=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")
IP_V6=$(timeout 1 ip -6 addr show scope global 2>/dev/null | grep inet6 | awk '{print $2}' | cut -d'/' -f1 | head -n 1 || echo "")
[ -z "$IP_V6" ] && IP_V6="N/A"
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")

# --- Network Speed Calculation ---
# Get network stats (exclude loopback)
NET_STATS=$(cat /proc/net/dev 2>/dev/null | grep -v "lo:" | grep -v "inter-|face" | tail -n +3 | tr -d '\r' | head -n 1)
RX_BYTES=$(echo "$NET_STATS" | awk '{print $2}' | tr -d ' ' || echo "0")
TX_BYTES=$(echo "$NET_STATS" | awk '{print $10}' | tr -d ' ' || echo "0")

# Try to get previous stats from temp file for speed calculation
NET_STATS_FILE="/tmp/sysinfo_net_stats"
if [ -f "$NET_STATS_FILE" ]; then
    PREV_RX=$(cat "$NET_STATS_FILE" 2>/dev/null | cut -d' ' -f1 || echo "0")
    PREV_TX=$(cat "$NET_STATS_FILE" 2>/dev/null | cut -d' ' -f2 || echo "0")
    PREV_TIME=$(cat "$NET_STATS_FILE" 2>/dev/null | cut -d' ' -f3 || echo "0")
else
    PREV_RX="0"
    PREV_TX="0"
    PREV_TIME="0"
fi

# Save current stats
CURRENT_TIME=$(date +%s)
echo "$RX_BYTES $TX_BYTES $CURRENT_TIME" > "$NET_STATS_FILE"

# Calculate speed if we have previous data (at least 1 second ago)
if [ "$PREV_TIME" -gt 0 ] && [ $((CURRENT_TIME - PREV_TIME)) -ge 1 ]; then
    TIME_DIFF=$((CURRENT_TIME - PREV_TIME))
    RX_DIFF=$((RX_BYTES - PREV_RX))
    TX_DIFF=$((TX_BYTES - PREV_TX))
    
    # Calculate speeds in KB/s
    if command -v bc >/dev/null 2>&1; then
        RX_SPEED=$(echo "scale=1; $RX_DIFF / 1024 / $TIME_DIFF" | bc -l | tr -d '\r' || echo "0")
        TX_SPEED=$(echo "scale=1; $TX_DIFF / 1024 / $TIME_DIFF" | bc -l | tr -d '\r' || echo "0")
    else
        RX_SPEED=$(awk "BEGIN {printf \"%.1f\", $RX_DIFF / 1024 / $TIME_DIFF}" | tr -d '\r' || echo "0")
        TX_SPEED=$(awk "BEGIN {printf \"%.1f\", $TX_DIFF / 1024 / $TIME_DIFF}" | tr -d '\r' || echo "0")
    fi
    
    # Format speeds - clean values before comparison
    RX_SPEED_CLEAN=$(echo "$RX_SPEED" | tr -d '\r' | tr -d ' ' | tr -d ' ')
    TX_SPEED_CLEAN=$(echo "$TX_SPEED" | tr -d '\r' | tr -d ' ' | tr -d ' ')

    if awk "BEGIN {exit !($RX_SPEED_CLEAN > 1024)}"; then
        RX_SPEED_FMT=$(awk "BEGIN {printf \"%.1f MB/s\", $RX_SPEED_CLEAN / 1024}" | tr -d '\r' || echo "0 KB/s")
    else
        RX_SPEED_FMT=$(awk "BEGIN {printf \"%.1f KB/s\", $RX_SPEED_CLEAN}" | tr -d '\r' || echo "0 KB/s")
    fi

    if awk "BEGIN {exit !($TX_SPEED_CLEAN > 1024)}"; then
        TX_SPEED_FMT=$(awk "BEGIN {printf \"%.1f MB/s\", $TX_SPEED_CLEAN / 1024}" | tr -d '\r' || echo "0 KB/s")
    else
        TX_SPEED_FMT=$(awk "BEGIN {printf \"%.1f KB/s\", $TX_SPEED_CLEAN}" | tr -d '\r' || echo "0 KB/s")
    fi
else
    # No previous data or not enough time passed
    RX_SPEED_FMT="0 KB/s"
    TX_SPEED_FMT="0 KB/s"
fi

# Try multiple methods to get CPU model
CPU_MODEL=""
if [ -f /proc/cpuinfo ]; then
    # Method 1: /proc/cpuinfo (most reliable)
    CPU_MODEL=$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | tr -d '\r' | awk -F: '{for(i=2;i<=NF;i++) printf "%s ", $i}' | tr -d '\r' | xargs 2>/dev/null || echo "")
fi
# Fallback to lscpu if /proc/cpuinfo didn't work
if [ -z "$CPU_MODEL" ] || [ "$CPU_MODEL" = "N/A" ]; then
    CPU_MODEL=$(timeout 1 lscpu 2>/dev/null | grep "Model name" | tr -d '\r' | sed 's/Model name: *//' | sed 's/BIOS.*//' | tr -d '\r' | xargs 2>/dev/null || echo "")
fi
# Final fallback
if [ -z "$CPU_MODEL" ] || [ "$CPU_MODEL" = "N/A" ]; then
    CPU_MODEL="N/A"
fi

# --- Print Dashboard ---
echo -e "${CYAN}================================================================${NONE}"
echo -e "  ${BOLD}$L_TITLE${NONE} - $(date +'%Y-%m-%d %H:%M:%S')"
echo -e "${CYAN}================================================================${NONE}"

printf "${GREEN}%-s${NONE}\n" "$L_CORE"
printf "  %-14s : %s\n" "$L_CPU" "$CPU_MODEL"
printf "  %-14s : %-18s %-12s : %s\n" "$L_IPV4" "$IP_V4" "$L_IPV6" "$IP_V6"
printf "  %-14s : %s\n" "$L_UPTIME" "$UPTIME"
echo ""

printf "${GREEN}%-s${NONE}\n" "$L_RES"
printf "  %-14s : %-18s %-12s : %s\n" "$L_LOAD" "$CPU_USAGE" "$L_PROCS" "$PROCESSES"
printf "  %-14s : %-18s %-12s : %s\n" "$L_MEM" "$MEM_INFO" "$L_USERS" "$USERS_LOGGED"
printf "  %-14s : %s\n" "$L_SWAP" "$SWAP_USAGE"
echo ""

printf "${GREEN}%-s${NONE}\n" "$L_NET"
printf "  %-14s : %-18s %-12s : %s\n" "$L_DOWNLOAD" "$RX_SPEED_FMT" "$L_UPLOAD" "$TX_SPEED_FMT"
echo ""

printf "${GREEN}%-s${NONE}\n" "$L_DISK"
printf "  %-18s %-8s %-8s %-8s %-15s\n" "$L_MNT" "$L_SIZE" "$L_USED" "$L_PERC" "$L_PROG"
echo -e "  --------------------------------------------------------------"
df -h -x tmpfs -x devtmpfs -x squashfs -x debugfs | grep '^/' | while IFS= read -r line; do
    MNT=$(echo $line | awk '{print $6}')
    SIZE=$(echo $line | awk '{print $2}')
    USED=$(echo $line | awk '{print $3}')
    PERC=$(echo $line | awk '{print $5}')
    PERC_NUM=$(echo $PERC | tr -d '%')
    printf "  %-18s %-8s %-8s %-8s [" "$MNT" "$SIZE" "$USED" "$PERC"
    draw_bar $PERC_NUM 10
    printf "]\n"
done
echo -e "${CYAN}================================================================${NONE}"
