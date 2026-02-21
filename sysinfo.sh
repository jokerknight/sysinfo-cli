#!/bin/bash

# --- Colors ---
NONE='\033[0m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'

# --- Labels ---
L_TITLE="SysInfo-Cli System Real-time Monitor"
L_CORE="[Core Info]"
L_RES="[Resource Usage]"
L_DISK="[Disk Status]"
L_CPU="CPU Model"
L_IPV4="IPv4 Addr"
L_IPV6="IPv6 Addr"
L_NAT="NAT Ports"
L_UPTIME="Uptime"
L_LOAD="CPU Load"
L_PROCS="Processes"
L_MEM="Memory"
L_USERS="Users Logged"
L_SWAP="Swap Usage"
L_NET="[Network Speed]"
L_UPLOAD="Upload"
L_DOWNLOAD="Download"
L_MNT="Mount"
L_SIZE="Size"
L_USED="Used"
L_PERC="Perm"
L_PROG="Progress"
L_MONTHLY="[Monthly Traffic]"
L_UPLOADED="Uploaded"
L_DOWNLOADED="Downloaded"
L_TOTAL="Total Used"
L_LIMIT="Limit"
L_TRAFFIC_PERC="Traffic %"
L_TRAFFIC_MODE="Traffic Mode"

# --- Progress Bar Function ---
draw_bar() {
    local perc=$1
    local max_len=$2
    # Ensure perc is numeric and within bounds
    perc=${perc:-0}
    [ "$perc" -lt 0 ] && perc=0
    [ "$perc" -gt 100 ] && perc=100

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

# --- Traffic Statistics Functions ---
# Convert bytes to human readable format
bytes_to_human() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt $((1024*1024)) ]; then
        echo "$(( bytes / 1024 ))KB"
    elif [ "$bytes" -lt $((1024*1024*1024)) ]; then
        echo "$(( bytes / 1024 / 1024 ))MB"
    elif [ "$bytes" -lt $((1024*1024*1024*1024)) ]; then
        echo "$(( bytes / 1024 / 1024 / 1024 ))GB"
    else
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes / 1024 / 1024 / 1024 / 1024}")TB"
    fi
}

# Initialize or reset monthly traffic stats
init_traffic_stats() {
    local current_rx=$1
    local current_tx=$2
    local traffic_mode=${3:-both}
    local current_time=$(date +%s)
    # Save current network values as baseline for next update
    echo "{\"start_time\":$current_time,\"rx_bytes\":0,\"tx_bytes\":0,\"last_rx\":$current_rx,\"last_tx\":$current_tx,\"traffic_mode\":\"$traffic_mode\",\"last_update\":$current_time}"
}

# Perform monthly traffic reset
perform_reset() {
    local stats_file="/etc/sysinfo-traffic.json"
    # Read traffic mode from config
    local config_file="/etc/sysinfo-traffic"
    local traffic_mode=$(cat "$config_file" 2>/dev/null | grep -o '"traffic_mode":"[^"]*"' | cut -d: -f2 | tr -d '"')
    traffic_mode=${traffic_mode:-both}
    # Get current network values for baseline
    local reset_rx=0
    local reset_tx=0
    while read -r line; do
        if [ -n "$line" ]; then
            local iface_rx=$(echo "$line" | awk '{print $2}' | tr -d ' ' || echo "0")
            local iface_tx=$(echo "$line" | awk '{print $10}' | tr -d ' ' || echo "0")
            reset_rx=$((reset_rx + iface_rx))
            reset_tx=$((reset_tx + iface_tx))
        fi
    done < <(cat /proc/net/dev 2>/dev/null | grep -v "lo:" | grep -v "inter-|face" | tail -n +3 | tr -d '\r')
    # Reset stats to zero with current network as baseline
    init_traffic_stats "$reset_rx" "$reset_tx" "$traffic_mode" | sudo tee "$stats_file" >/dev/null 2>&1
}

# Update traffic statistics
update_traffic_stats() {
    local stats_file="/etc/sysinfo-traffic.json"
    local config_file="/etc/sysinfo-traffic"
    local current_rx=$1
    local current_tx=$2

    # Check if config exists
    if [ ! -f "$config_file" ]; then
        return 0
    fi

    # Read config
    local reset_day=$(cat "$config_file" 2>/dev/null | grep -o '"reset_day":[0-9]*' | cut -d: -f2)
    reset_day=${reset_day:-1}

    # Initialize stats if not exists
    if [ ! -f "$stats_file" ]; then
        # Need to get current network values first
        local init_rx=0
        local init_tx=0
        while read -r line; do
            if [ -n "$line" ]; then
                local iface_rx=$(echo "$line" | awk '{print $2}' | tr -d ' ' || echo "0")
                local iface_tx=$(echo "$line" | awk '{print $10}' | tr -d ' ' || echo "0")
                init_rx=$((init_rx + iface_rx))
                init_tx=$((init_tx + iface_tx))
            fi
        done < <(cat /proc/net/dev 2>/dev/null | grep -v "lo:" | grep -v "inter-|face" | tail -n +3 | tr -d '\r')
        init_traffic_stats "$init_rx" "$init_tx" | sudo tee "$stats_file" >/dev/null 2>&1
    fi

    # Read current stats
    local start_time=$(cat "$stats_file" 2>/dev/null | grep -o '"start_time":[0-9]*' | cut -d: -f2)
    start_time=${start_time:-$(date +%s)}
    local rx_bytes=$(cat "$stats_file" 2>/dev/null | grep -o '"rx_bytes":[0-9]*' | cut -d: -f2)
    rx_bytes=${rx_bytes:-0}
    local tx_bytes=$(cat "$stats_file" 2>/dev/null | grep -o '"tx_bytes":[0-9]*' | cut -d: -f2)
    tx_bytes=${tx_bytes:-0}

    # Check if month reset is needed
    # Reset when:
    # - Current day is the reset day
    # - AND the recorded start_time is from a previous month or is from today but before this run
    local current_day=$(date +%d)
    local current_month=$(date +%m)
    local current_year=$(date +%Y)
    local current_day_seconds=$(date -d "$(date +%Y-%m-01)" +%s)

    # Get last update time (fallback to start_time if not set)
    local last_update=$(cat "$stats_file" 2>/dev/null | grep -o '"last_update":[0-9]*' | cut -d: -f2)
    last_update=${last_update:-$start_time}
    local last_month=$(date -d "@$last_update" +%m 2>/dev/null || date +%m)
    local last_year=$(date -d "@$last_update" +%Y 2>/dev/null || date +%Y)

    # Check if reset is needed:
    # - Current day is the reset day
    # - AND (month changed OR year changed OR (same month but last_update was before today))
    if [ "$current_day" -eq "$reset_day" ]; then
        local current_day_start=$(date -d "$(date +%Y-%m-%d) 00:00:00" +%s)
        if [ "$current_month" -ne "$last_month" ] || [ "$current_year" -ne "$last_year" ]; then
            # Month/year changed - need reset
            perform_reset
            return 0
        fi
    fi

    # Normal update flow
    # Use passed values if provided, otherwise read from network
    if [ -z "$current_rx" ] || [ -z "$current_tx" ]; then
        current_rx=0
        current_tx=0
        while read -r line; do
            if [ -n "$line" ]; then
                local iface_rx=$(echo "$line" | awk '{print $2}' | tr -d ' ' || echo "0")
                local iface_tx=$(echo "$line" | awk '{print $10}' | tr -d ' ' || echo "0")
                current_rx=$((current_rx + iface_rx))
                current_tx=$((current_tx + iface_tx))
            fi
        done < <(cat /proc/net/dev 2>/dev/null | grep -v "lo:" | grep -v "inter-|face" | tail -n +3 | tr -d '\r')
    fi

    # Read last update values
    local last_rx_bytes=$(cat "$stats_file" 2>/dev/null | grep -o '"last_rx":[0-9]*' | cut -d: -f2)
    last_rx_bytes=${last_rx_bytes:-0}
    local last_tx_bytes=$(cat "$stats_file" 2>/dev/null | grep -o '"last_tx":[0-9]*' | cut -d: -f2)
    last_tx_bytes=${last_tx_bytes:-0}

    # Calculate delta (handle counter overflow)
    local rx_delta=$((current_rx - last_rx_bytes))
    local tx_delta=$((current_tx - last_tx_bytes))

    # Handle overflow (counter wrapped around)
    # If delta is negative or too large (>1GB), assume counter reset
    if [ "$rx_delta" -lt 0 ] || [ "$rx_delta" -gt 1073741824 ]; then
        # Counter reset, ignore this update but use current as new baseline
        rx_delta=0
    fi
    if [ "$tx_delta" -lt 0 ] || [ "$tx_delta" -gt 1073741824 ]; then
        tx_delta=0
    fi

    # Add delta to accumulated traffic
    rx_bytes=$((rx_bytes + rx_delta))
    tx_bytes=$((tx_bytes + tx_delta))

    # Get traffic mode from stats file (preserve it)
    local traffic_mode=$(cat "$stats_file" 2>/dev/null | grep -o '"traffic_mode":"[^"]*"' | cut -d: -f2 | tr -d '"')
    traffic_mode=${traffic_mode:-both}

    # Save updated stats
    local current_time=$(date +%s)
    echo "{\"start_time\":$start_time,\"rx_bytes\":$rx_bytes,\"tx_bytes\":$tx_bytes,\"last_rx\":$current_rx,\"last_tx\":$current_tx,\"traffic_mode\":\"$traffic_mode\",\"last_update\":$current_time}" | sudo tee "$stats_file" >/dev/null 2>&1
}

# Get traffic statistics for display
get_traffic_stats() {
    local stats_file="/etc/sysinfo-traffic.json"
    local config_file="/etc/sysinfo-traffic"

    # Check if config exists
    if [ ! -f "$config_file" ]; then
        return 1
    fi

    # Initialize stats file if not exists
    if [ ! -f "$stats_file" ]; then
        init_traffic_stats | sudo tee "$stats_file" >/dev/null 2>&1
    fi

    # Read config
    local limit=$(cat "$config_file" 2>/dev/null | grep -o '"limit":"[^"]*"' | cut -d: -f2 | tr -d '"')
    limit=${limit:-1T}

    # Convert limit to bytes - extract number and unit
    local num="${limit%[TGM]}"
    local unit="${limit: -1}"
    case "$unit" in
        T) local limit_bytes=$(( num * 1024 * 1024 * 1024 * 1024 )) ;;
        G) local limit_bytes=$(( num * 1024 * 1024 * 1024 )) ;;
        M) local limit_bytes=$(( num * 1024 * 1024 )) ;;
        *) local limit_bytes=$((1024 * 1024 * 1024 * 1024)) ;;
    esac

    # Verify limit_bytes was set
    [ -z "$limit_bytes" ] || [ "$limit_bytes" -eq 0 ] && limit_bytes=$((1024 * 1024 * 1024 * 1024))

    # Read stats
    local rx_bytes=$(cat "$stats_file" 2>/dev/null | grep -o '"rx_bytes":[0-9]*' | cut -d: -f2)
    rx_bytes=${rx_bytes:-0}
    local tx_bytes=$(cat "$stats_file" 2>/dev/null | grep -o '"tx_bytes":[0-9]*' | cut -d: -f2)
    tx_bytes=${tx_bytes:-0}

    # Read traffic mode from config (default to both)
    local traffic_mode=$(cat "$config_file" 2>/dev/null | grep -o '"traffic_mode":"[^"]*"' | cut -d: -f2 | tr -d '"')
    traffic_mode=${traffic_mode:-both}

    # Calculate total based on traffic mode
    local total_bytes
    case "$traffic_mode" in
        upload)
            total_bytes=$tx_bytes
            ;;
        download)
            total_bytes=$rx_bytes
            ;;
        both|*)
            total_bytes=$((rx_bytes + tx_bytes))
            ;;
    esac

    # Calculate percentage - use awk to handle large numbers
    local perc=$(awk "BEGIN {printf \"%.0f\", ($total_bytes * 100) / $limit_bytes}")
    [ -z "$perc" ] && perc=0
    if [ "$perc" -gt 100 ]; then perc=100; fi

    # Format output
    TRAFFIC_UP=$(bytes_to_human $tx_bytes)
    TRAFFIC_DOWN=$(bytes_to_human $rx_bytes)
    TRAFFIC_TOTAL=$(bytes_to_human $total_bytes)
    TRAFFIC_LIMIT=$limit
    TRAFFIC_PERC="${perc}%"

    # Set traffic mode for display
    case "$traffic_mode" in
        upload) TRAFFIC_MODE="Upload Only" ;;
        download) TRAFFIC_MODE="Download Only" ;;
        both|*) TRAFFIC_MODE="Bi-directional" ;;
    esac

    return 0
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

# Get IPv6 address - prioritize physical ethernet interfaces (en*, eth*)
# Then fallback to other interfaces, excluding temporary addresses
get_ipv6() {
    local interfaces="$1"
    timeout 1 ip -6 addr show scope global $interfaces 2>/dev/null | grep inet6 | grep -v "temporary" | awk '{print $2}' | cut -d'/' -f1 | sort | head -n 1 || echo ""
}

# Try physical ethernet interfaces first (en*, eth*)
IP_V6=$(get_ipv6 "en*" 2>/dev/null)
if [ -z "$IP_V6" ]; then
    IP_V6=$(get_ipv6 "eth*" 2>/dev/null)
fi
# Fallback: get from any global interface (sorted for consistency)
if [ -z "$IP_V6" ]; then
    IP_V6=$(timeout 1 ip -6 addr show scope global 2>/dev/null | grep inet6 | grep -v "temporary" | awk '{print $2}' | cut -d'/' -f1 | sort | head -n 1 || echo "")
fi
# Last fallback: include temporary addresses
if [ -z "$IP_V6" ]; then
    IP_V6=$(timeout 1 ip -6 addr show scope global 2>/dev/null | grep inet6 | awk '{print $2}' | cut -d'/' -f1 | sort | head -n 1 || echo "")
fi
[ -z "$IP_V6" ] && IP_V6="N/A"
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")

# --- Network Speed Calculation ---
# Get network stats (exclude loopback) - sum all interfaces
RX_BYTES=0
TX_BYTES=0
while read -r line; do
    if [ -n "$line" ]; then
        iface_rx=$(echo "$line" | awk '{print $2}' | tr -d ' ' || echo "0")
        iface_tx=$(echo "$line" | awk '{print $10}' | tr -d ' ' || echo "0")
        RX_BYTES=$((RX_BYTES + iface_rx))
        TX_BYTES=$((TX_BYTES + iface_tx))
    fi
done < <(cat /proc/net/dev 2>/dev/null | grep -v "lo:" | grep -v "inter-|face" | tail -n +3 | tr -d '\r')

# Try to get previous stats from temp file for speed calculation
# Use /var/tmp for better permission handling
NET_STATS_FILE="/var/tmp/sysinfo_net_stats_${USER:-root}"
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
echo "$RX_BYTES $TX_BYTES $CURRENT_TIME" > "$NET_STATS_FILE" 2>/dev/null

# Update monthly traffic statistics - pass current stats
update_traffic_stats "$RX_BYTES" "$TX_BYTES"

# Get traffic statistics for display
get_traffic_stats
TRAFFIC_AVAILABLE=$?

# Validate variables are numeric
PREV_TIME=${PREV_TIME:-0}
PREV_RX=${PREV_RX:-0}
PREV_TX=${PREV_TX:-0}
CURRENT_TIME=${CURRENT_TIME:-$(date +%s)}
RX_BYTES=${RX_BYTES:-0}
TX_BYTES=${TX_BYTES:-0}

# Ensure they are numeric
[[ ! "$PREV_TIME" =~ ^[0-9]+$ ]] && PREV_TIME=0
[[ ! "$PREV_RX" =~ ^[0-9]+$ ]] && PREV_RX=0
[[ ! "$PREV_TX" =~ ^[0-9]+$ ]] && PREV_TX=0
[[ ! "$CURRENT_TIME" =~ ^[0-9]+$ ]] && CURRENT_TIME=$(date +%s)
[[ ! "$RX_BYTES" =~ ^[0-9]+$ ]] && RX_BYTES=0
[[ ! "$TX_BYTES" =~ ^[0-9]+$ ]] && TX_BYTES=0

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

# Load NAT config if exists
NAT_RANGE=""
if [ -f /etc/sysinfo-nat ]; then
    NAT_RANGE=$(cat /etc/sysinfo-nat 2>/dev/null | xargs || echo "")
    # Convert 1-2 format to 1->2 for display
    NAT_RANGE=$(echo "$NAT_RANGE" | sed 's/\([0-9]\)-\([0-9]\)/\1->\2/g')
fi

# --- Print Dashboard ---
echo -e "${CYAN}================================================================${NONE}"
echo -e "  ${BOLD}$L_TITLE${NONE} - $(date +'%Y-%m-%d %H:%M:%S')"
echo -e "${CYAN}================================================================${NONE}"

printf "${GREEN}%-s${NONE}\n" "$L_CORE"
printf "  %-14s : %s (%s core(s))\n" "$L_CPU" "$CPU_MODEL" "$CPU_CORES"
printf "  %-14s : %s\n" "$L_IPV4" "$IP_V4"
printf "  %-14s : %s\n" "$L_IPV6" "$IP_V6"
if [ -n "$NAT_RANGE" ]; then
    printf "  %-14s : %s\n" "$L_NAT" "$NAT_RANGE"
fi
printf "  %-14s : %s\n" "$L_UPTIME" "$UPTIME"

printf "${GREEN}%-s${NONE}\n" "$L_RES"
printf "  %-14s : %-18s %-12s : %s\n" "$L_LOAD" "$CPU_USAGE" "$L_PROCS" "$PROCESSES"
printf "  %-14s : %-18s %-12s : %s\n" "$L_MEM" "$MEM_INFO" "$L_USERS" "$USERS_LOGGED"
printf "  %-14s : %s\n" "$L_SWAP" "$SWAP_USAGE"

printf "${GREEN}%-s${NONE}\n" "$L_NET"
if [ "$TRAFFIC_AVAILABLE" -eq 0 ]; then
    printf "  %-14s : %-18s %-12s : %s\n" "$L_DOWNLOAD" "$RX_SPEED_FMT ($TRAFFIC_DOWN)" "$L_UPLOAD" "$TX_SPEED_FMT ($TRAFFIC_UP)"
    printf "  %-14s : %-18s %-12s : %s\n" "$L_TOTAL" "$TRAFFIC_TOTAL" "$L_LIMIT" "$TRAFFIC_LIMIT"
    printf "  %-14s : %s\n" "$L_TRAFFIC_MODE" "$TRAFFIC_MODE"
    TRAFFIC_PERC_NUM=$(echo "$TRAFFIC_PERC" | tr -d '%')
    TRAFFIC_PERC_NUM=${TRAFFIC_PERC_NUM:-0}
    printf "  %-14s : [" "$L_TRAFFIC_PERC"
    draw_bar $TRAFFIC_PERC_NUM 10
    printf "] %s\n" "$TRAFFIC_PERC"
else
    printf "  %-14s : %-18s %-12s : %s\n" "$L_DOWNLOAD" "$RX_SPEED_FMT" "$L_UPLOAD" "$TX_SPEED_FMT"
fi

printf "${GREEN}%-s${NONE}\n" "$L_DISK"
printf "  %-18s %-8s %-8s %-8s %-15s\n" "$L_MNT" "$L_SIZE" "$L_USED" "$L_PERC" "$L_PROG"
echo -e "  -------------------------------------------------------------"
df -h -x tmpfs -x devtmpfs -x squashfs -x debugfs -x overlay -x efivarfs 2>/dev/null | tail -n +2 | while IFS=' ' read -r filesystem size used avail perc mnt rest; do
    # Only show if mount point starts with / and is valid
    # Skip efi partition and other system partitions
    if [ -n "$mnt" ] && [[ "$mnt" == /* ]]; then
        # Skip /boot/efi and similar system partitions
        if [[ "$mnt" == /boot/efi ]] || [[ "$mnt" == /boot ]]; then
            continue
        fi
        # Truncate long mount paths to 18 characters
        if [ ${#mnt} -gt 18 ]; then
            mnt="${mnt:0:15}..."
        fi
        PERC_NUM=$(echo "$perc" | tr -d '%')
        printf "  %-18s %-8s %-8s %-8s [" "$mnt" "$size" "$used" "$perc"
        draw_bar $PERC_NUM 10
        printf "]\n"
    fi
done
echo -e "${CYAN}================================================================${NONE}"
