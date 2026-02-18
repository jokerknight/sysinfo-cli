#!/bin/bash
GITHUB_RAW="https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main"

# Detect if in China and use mirror
check_china() {
    # Test connectivity to raw.githubusercontent.com
    if timeout 3 curl -s -I https://github.com &>/dev/null; then
        echo "false"
    else
        echo "true"
    fi
}

CHINA_ACCESS=$(check_china)
if [ "$CHINA_ACCESS" = "true" ]; then
    echo "Detected China access, using mirror..."
    GITHUB_RAW="https://gh.277177.xyz/$GITHUB_RAW"
fi

# Parse NAT port mapping parameter (supports -NAT 1->2 2->3 or -NAT1->2)
NAT_RANGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -NAT*|-nat*)
            # Check if format is -NATrange or -NAT range1 range2 ...
            if [[ "$1" == -NAT?* ]] || [[ "$1" == -nat?* ]]; then
                NAT_RANGE="${1#-[Nn][Aa][Tt]}"
            else
                # Collect all remaining arguments as NAT mappings
                shift
                NAT_RANGE="$*"
                break
            fi
            ;;
    esac
    shift
done

# Clean up old installation first
echo "Cleaning up old installation..."
sudo rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main /etc/sysinfo-lang /etc/sysinfo-nat

echo "Starting installation..."

# Save NAT config if provided
if [ -n "$NAT_RANGE" ]; then
    echo "NAT_RANGE=$NAT_RANGE" | sudo tee /etc/sysinfo-nat >/dev/null
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Try to use local sysinfo.sh first, fallback to download
# Handle special case when script is executed via bash <(curl ...)
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

# Create 'sysinfo' command for real-time monitoring using watch
sudo bash -c "cat > /usr/local/bin/sysinfo <<'EOF'
#!/bin/bash

# Handle -NAT/-nat parameter for NAT port configuration
if [[ "\$1" == -NAT* ]] || [[ "\$1" == -nat* ]]; then
    NAT_RANGE=""
    if [[ "\$1" == -NAT?* ]] || [[ "\$1" == -nat?* ]]; then
        NAT_RANGE="\${1#-[Nn][Aa][Tt]}"
    else
        shift
        NAT_RANGE="\$*"
    fi
    if [ -n "\$NAT_RANGE" ]; then
        echo "NAT_RANGE=\$NAT_RANGE" | sudo tee /etc/sysinfo-nat >/dev/null
        echo "NAT port mappings: \$NAT_RANGE"
    else
        echo "Usage: sysinfo -NAT <mapping1> <mapping2> ..."
        echo "Example: sysinfo -NAT 1->2 2->3"
    fi
    exit 0
fi

# Get refresh interval from argument (default 1 second)
INTERVAL=\${1:-1}
# Validate interval is numeric
case \$INTERVAL in
    ''|*[!0-9]*)
        INTERVAL=1
        ;;
esac
# Use watch for smooth, flicker-free refresh
# -c: interpret ANSI color sequences
# -n: refresh interval in seconds
# -t: disable title (we show our own)
watch -c -n \$INTERVAL -t bash /etc/profile.d/sysinfo.sh 2>/dev/null
EOF"
sudo chmod +x /usr/local/bin/sysinfo

echo "Done! Re-login to see system info at login, or type 'sysinfo' for real-time monitoring."
echo ""
echo "Usage:"
echo "  sysinfo       - Real-time monitoring with 1 second refresh"
echo "  sysinfo 2     - Real-time monitoring with 2 seconds refresh"
echo "  sysinfo 5     - Real-time monitoring with 5 seconds refresh"