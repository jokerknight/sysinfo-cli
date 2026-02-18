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

# Validate NAT mapping format (e.g., 8080-80)
validate_nat_mapping() {
    local mapping="$1"
    if [[ ! "$mapping" =~ ^[0-9]+-[0-9]+$ ]]; then
        echo "Error: Invalid NAT mapping format '$mapping'"
        echo ""
        echo "Expected format: port1-port2 (use '-' not '->')"
        echo "  Correct: NAT 8080-80"
        echo "  Wrong:   NAT 8080->80  (causes shell redirection)"
        return 1
    fi
    return 0
}

# Validate multiple NAT mappings
validate_nat_mappings() {
    local mappings="$1"
    local valid=true
    for mapping in $mappings; do
        if ! validate_nat_mapping "$mapping"; then
            valid=false
        fi
    done
    [ "$valid" = "true" ]
}

# Save NAT mappings to config file
save_nat_mappings() {
    local mappings="$1"
    echo "$mappings" | sudo tee /etc/sysinfo-nat >/dev/null
    echo "NAT port mappings: $mappings"
}

# Parse command line arguments for NAT parameters
parse_nat_args() {
    local -n _nat_range=$1
    local -n _clear_nat=$2
    shift 2

    for ((i=0; i<$#; i++)); do
        local arg="${!i}"
        local arg_lower="${arg,,}"
        case "$arg_lower" in
            --clear-nat)
                _clear_nat=1
                return
                ;;
            nat|-nat)
                # Collect remaining args until next flag
                for ((j=i+1; j<=$#; j++)); do
                    local next_arg="${!j}"
                    local next_lower="${next_arg,,}"
                    if [[ "$next_lower" == nat* ]] || [[ "$next_lower" == --clear-nat ]]; then
                        break
                    fi
                    if [ -z "$_nat_range" ]; then
                        _nat_range="$next_arg"
                    else
                        _nat_range="$_nat_range $next_arg"
                    fi
                done
                return
                ;;
            nat-*|-nat-*)
                # Format: NAT8080-80 or -NAT8080-80
                _nat_range="${arg#nat-}"
                _nat_range="${_nat_range#-nat-}"
                return
                ;;
        esac
    done
}

# Install sysinfo.sh
install_sysinfo_sh() {
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
}

# Create /usr/local/bin/sysinfo wrapper command
create_sysinfo_command() {
    sudo tee /usr/local/bin/sysinfo > /dev/null << 'CMD'
#!/bin/bash

# Handle help
case "${1,,}" in
    help|--help|-h)
        echo "SysInfo-Cli - System Real-time Monitor"
        echo ""
        echo "Usage:"
        echo "  sysinfo [interval]      - Real-time monitoring (default: 1s refresh)"
        echo "  sysinfo 2              - Real-time monitoring with 2s refresh"
        echo "  sysinfo 5              - Real-time monitoring with 5s refresh"
        echo ""
        echo "NAT Port Mapping:"
        echo "  sysinfo NAT 1-2        - Set NAT port mapping"
        echo "  sysinfo NAT 1-2 2-3    - Set multiple NAT port mappings"
        echo "  sysinfo --clear-nat    - Clear NAT port mappings"
        echo ""
        exit 0
        ;;
esac

# Handle NAT parameters
case "${1,,}" in
    --clear-nat)
        sudo rm -f /etc/sysinfo-nat
        echo "NAT port mappings cleared"
        exit 0
        ;;
    nat|-nat)
        shift
        mappings="$*"
        if [ -n "$mappings" ]; then
            for mapping in $mappings; do
                if [[ ! "$mapping" =~ ^[0-9]+-[0-9]+$ ]]; then
                    echo "Error: Invalid NAT mapping format '$mapping'"
                    echo ""
                    echo "Expected format: port1-port2 (use '-' not '->')"
                    echo "  Correct: NAT 8080-80"
                    echo "  Wrong:   NAT 8080->80  (causes shell redirection)"
                    exit 1
                fi
            done
            echo "$mappings" | sudo tee /etc/sysinfo-nat >/dev/null
            echo "NAT port mappings: $mappings"
        else
            echo "Usage: sysinfo NAT mapping1 mapping2 ..."
            echo "Example: sysinfo NAT 1-2 2-3"
        fi
        exit 0
        ;;
    nat-*|-nat-*)
        mappings="${1#nat-}"
        mappings="${mappings#-nat-}"
        if [ -n "$mappings" ]; then
            if [[ ! "$mappings" =~ ^[0-9]+-[0-9]+$ ]]; then
                echo "Error: Invalid NAT mapping format '$mappings'"
                echo ""
                echo "Expected format: port1-port2 (use '-' not '->')"
                echo "  Correct: NAT 8080-80"
                echo "  Wrong:   NAT 8080->80  (causes shell redirection)"
                exit 1
            fi
            echo "$mappings" | sudo tee /etc/sysinfo-nat >/dev/null
            echo "NAT port mappings: $mappings"
        else
            echo "Usage: sysinfo NAT mapping1 mapping2 ..."
            echo "Example: sysinfo NAT 1-2 2-3"
        fi
        exit 0
        ;;
esac

# Get refresh interval (default 1 second)
INTERVAL=${1:-1}
case $INTERVAL in
    ''|*[!0-9]*)
        INTERVAL=1
        ;;
esac

# Start monitoring with watch
watch -c -n $INTERVAL -t bash /etc/profile.d/sysinfo.sh 2>/dev/null
CMD
    sudo chmod +x /usr/local/bin/sysinfo
}

# Print usage information
print_usage() {
    echo "Usage:"
    echo "  sysinfo              - Real-time monitoring with 1s refresh"
    echo "  sysinfo [N]          - Real-time monitoring with N seconds refresh"
    echo "  sysinfo NAT 1-2      - Set NAT port mapping (1-2 = public->private)"
    echo "  sysinfo --clear-nat   - Clear NAT port mappings"
    echo ""
    echo "Installation with NAT mappings:"
    echo "  ./install.sh NAT 1-2 2-3"
}

# ============================================
# Main Installation Process
# ============================================

# Check for China access and use mirror if needed
CHINA_ACCESS=$(check_china)
if [ "$CHINA_ACCESS" = "true" ]; then
    echo "Detected China access, using mirror..."
    GITHUB_RAW="https://gh.277177.xyz/$GITHUB_RAW"
fi

# Parse NAT arguments
NAT_RANGE=""
CLEAR_NAT=0
parse_nat_args NAT_RANGE CLEAR_NAT "$@"

# Clean up old installation
echo "Cleaning up old installation..."
sudo rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh \
         /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main \
         /etc/sysinfo-lang /etc/sysinfo-nat

echo "Starting installation..."

# Handle NAT configuration
if [ "$CLEAR_NAT" = "1" ]; then
    echo "NAT port mappings cleared"
elif [ -n "$NAT_RANGE" ]; then
    if validate_nat_mappings "$NAT_RANGE"; then
        save_nat_mappings "$NAT_RANGE"
    else
        echo "Installation aborted due to invalid NAT mappings."
        exit 1
    fi
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install sysinfo.sh
install_sysinfo_sh

# Create sysinfo command
create_sysinfo_command

# Installation complete
echo "Done! Re-login to see system info at login, or type 'sysinfo' for real-time monitoring."
echo ""
print_usage
