#!/bin/bash
GITHUB_RAW="https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main"

# ============================================
# Functions
# ============================================

# Detect if in China and use mirror
check_china() {
    if timeout 3 curl -s -I https://github.com &>/dev/null; then
        echo "false"
    else
        echo "true"
    fi
}

# Print usage information
print_usage() {
    echo "Usage:"
    echo "  ./install.sh          - Install sysinfo-cli (default)"
    echo "  ./install.sh --help  - Show this help"
    echo ""
    echo "After installation, use 'sysinfo' command to:"
    echo "  - View system info"
    echo "  - Configure NAT port mappings:   sysinfo --nat 8080-80"
    echo "  - Configure traffic limit:      sysinfo --traffic 500G"
    echo "  - Configure throttling:         sysinfo --limit enable 95 1mbps"
    echo "  - Combine multiple settings:    sysinfo --nat 1-2 --traffic 1T --limit enable"
    echo ""
    echo "Other options:"
    echo "  sysinfo --help        - Show sysinfo help"
    echo "  sysinfo --clear-nat   - Clear NAT mappings"
    echo "  sysinfo --reset-traffic - Reset traffic stats"
}

# ============================================
# Main Installation Process
# ============================================

# Show help
if [ "$#" -gt 0 ]; then
    case "$1" in
        --help|-h|help)
            print_usage
            exit 0
            ;;
    esac
fi

# Check for China access and use mirror if needed
CHINA_ACCESS=$(check_china)
if [ "$CHINA_ACCESS" = "true" ]; then
    echo "Detected China access, using mirror..."
    GITHUB_RAW="https://gh.277177.xyz/$GITHUB_RAW"
fi

# Clean up old installation
echo "Cleaning up old installation..."

# Best-effort runtime cleanup: clear active tc/ifb throttling state from previous installs
if command -v tc >/dev/null 2>&1 && command -v ip >/dev/null 2>&1; then
    while read -r IFACE; do
        [ -n "$IFACE" ] || continue
        [ "$IFACE" = "lo" ] && continue
        sudo tc qdisc del dev "$IFACE" root >/dev/null 2>&1 || true
        sudo tc qdisc del dev "$IFACE" ingress >/dev/null 2>&1 || true
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)

    sudo tc qdisc del dev ifb_sysinfo0 root >/dev/null 2>&1 || true
fi

sudo rm -f /var/tmp/sysinfo_throttle_state

sudo rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh \
         /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main \
         /etc/sysinfo-lang /etc/sysinfo-nat /etc/sysinfo-traffic /etc/sysinfo-traffic.json
sudo rm -f /var/tmp/sysinfo_net_stats_*

echo "Starting installation..."

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install sysinfo.sh
if [[ "${BASH_SOURCE[0]}" == /dev/fd/* ]]; then
    echo "Downloading sysinfo.sh from $GITHUB_RAW/sysinfo.sh..."
    sudo curl -sSL "$GITHUB_RAW/sysinfo.sh" -o /etc/profile.d/sysinfo.sh
elif [ -f "$SCRIPT_DIR/sysinfo.sh" ]; then
    echo "Using local sysinfo.sh..."
    sudo cp "$SCRIPT_DIR/sysinfo.sh" /etc/profile.d/sysinfo.sh
else
    echo "Downloading sysinfo.sh from $GITHUB_RAW/sysinfo.sh..."
    sudo curl -sSL "$GITHUB_RAW/sysinfo.sh" -o /etc/profile.d/sysinfo.sh
fi
sudo chmod +x /etc/profile.d/sysinfo.sh

# Create /usr/local/bin/sysinfo wrapper
sudo tee /usr/local/bin/sysinfo > /dev/null << 'CMD'
#!/bin/bash

show_help() {
    echo "SysInfo-Cli - System Real-time Monitor"
    echo ""
    echo "Usage:"
    echo "  sysinfo                          - Display system info"
    echo "  sysinfo [N]                      - Display with N seconds refresh"
    echo ""
    echo "Configuration Options:"
    echo "  --nat port1-port2 [port3-port4 ...]"
    echo "      Set NAT port mappings"
    echo ""
    echo "  --traffic limit [day] [mode]"
    echo "      Set traffic limit (e.g., 1T, 500G, 100M)"
    echo "      day:  Reset day (1-31)"
    echo "      mode: upload/download/both"
    echo ""
    echo "  --limit [enable|disable] [threshold] [rate]"
    echo "      Configure traffic throttling (TC-based)"
    echo "      NOTE: Upload/Download share unified HTB + fq_codel profile"
    echo "      NOTE: Download shaping uses IFB redirect + HTB"
    echo ""
    echo "Other Options:"
    echo "  --reset-traffic  Reset monthly traffic statistics"
    echo "  --clear-nat     Clear NAT port mappings"
    echo "  --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  sysinfo --nat 8080-80"
    echo "  sysinfo --nat 1-2 3-5"
    echo "  sysinfo --traffic 500G"
    echo "  sysinfo --traffic 500G 15         # 500G, reset on 15th"
    echo "  sysinfo --traffic 500G upload     # upload only"
    echo "  sysinfo --traffic 500G 15 upload  # 500G, reset on 15th, upload"
    echo "  sysinfo --limit enable 95 1mbps"
    echo "  sysinfo --limit disable"
    echo "  sysinfo --nat 1-2 --traffic 500G --limit enable 95 1mbps"
}

case "${1,,}" in
    help|--help|-h)
        show_help
        exit 0
        ;;
esac

# Support numeric interval argument: sysinfo 5
INTERVAL=1
if [ "$#" -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    INTERVAL="$1"
fi

# Non-numeric arguments are treated as configuration commands
if [ "$#" -gt 0 ] && ! [[ "$1" =~ ^[0-9]+$ && "$#" -eq 1 ]]; then
    bash /etc/profile.d/sysinfo.sh "$@"
    exit $?
fi

case "$INTERVAL" in
    ''|*[!0-9]*)
        INTERVAL=1
        ;;
esac

watch -c -n "$INTERVAL" -t bash /etc/profile.d/sysinfo.sh 2>/dev/null
CMD
sudo chmod +x /usr/local/bin/sysinfo

# Default traffic config
echo '{"limit":"1T","reset_day":1,"traffic_mode":"both"}' | sudo tee /etc/sysinfo-traffic >/dev/null

echo ""
echo "============================================"
echo "Installation complete!"
echo "============================================"
echo ""
echo "Usage:"
echo "  sysinfo              - Real-time monitoring (1s refresh)"
echo "  sysinfo 5            - Real-time monitoring (5s refresh)"
echo ""
echo "Configuration (run these after installation):"
echo "  sysinfo --nat 8080-80              # Set NAT port mapping"
echo "  sysinfo --traffic 500G             # Set traffic limit"
echo "  sysinfo --traffic 500G 15 upload   # With reset day and mode"
echo "  sysinfo --limit enable 95 1mbps   # Enable throttling"
echo "  sysinfo --limit disable            # Disable throttling"
echo "  sysinfo --clear-nat                # Clear NAT mappings"
echo "  sysinfo --reset-traffic            # Reset traffic stats"
echo ""
echo "Notes:"
echo "  - Re-running install.sh will clear active tc/ifb runtime limits"
echo "  - Then configure NAT/traffic/limit again via sysinfo"
echo ""
print_usage
