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
# Get CPU usage from top - extract idle percentage and calculate usage
CPU_USAGE_NUM=$(timeout 2 top -bn1 2>/dev/null | grep -m 1 "Cpu(s)" | sed -E 's/.*[ ,]([0-9.]+)%?id.*/\1/' | awk '{print 100 - $1}' || echo "0")
CPU_USAGE=$(printf "%.1f%%" $CPU_USAGE_NUM)
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
CPU_MODEL=$(timeout 1 lscpu 2>/dev/null | grep "Model name" | sed 's/Model name: *//' | sed 's/BIOS.*//' | xargs || echo "N/A")

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
