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

# Validate traffic limit format (e.g., 1T, 500G, 100M)
validate_traffic_limit() {
    local limit="$1"
    if [[ ! "$limit" =~ ^[0-9]+[TGM]$ ]]; then
        echo "Error: Invalid traffic limit format '$limit'"
        echo "Expected format: Number + Unit (T/G/M)"
        echo "  Examples: 1T, 500G, 100M"
        return 1
    fi
    return 0
}

# Convert traffic limit to bytes
traffic_to_bytes() {
    local limit="$1"
    local num="${limit%[TGM]}"
    local unit="${limit: -1}"

    case "$unit" in
        T) echo "$(( num * 1024 * 1024 * 1024 * 1024 ))" ;;
        G) echo "$(( num * 1024 * 1024 * 1024 ))" ;;
        M) echo "$(( num * 1024 * 1024 ))" ;;
    esac
}

# Save traffic limit config
save_traffic_config() {
    local limit="$1"
    local reset_day="$2"
    local traffic_mode="$3"

    echo "{\"limit\":\"$limit\",\"reset_day\":$reset_day,\"traffic_mode\":\"$traffic_mode\"}" | sudo tee /etc/sysinfo-traffic >/dev/null
    # Translate mode for display
    case "$traffic_mode" in
        upload) mode_display="upload only" ;;
        download) mode_display="download only" ;;
        both|*) mode_display="bi-directional" ;;
    esac
    echo "Traffic limit: $limit per month ($mode_display), reset on day $reset_day"
}

# Parse traffic limit arguments
parse_traffic_args() {
    local -n _traffic_limit=$1
    local -n _reset_day=$2
    local -n _traffic_mode=$3
    local _args=("$@")

    for ((i=0; i<${#_args[@]}; i++)); do
        local arg="${_args[$i]}"
        local arg_lower="${arg,,}"
        case "$arg_lower" in
            traffic|-traffic)
                # Get limit, reset day, and traffic mode
                if ((i+1 < ${#_args[@]})); then
                    local next_arg="${_args[$((i+1))]}"
                    # Check if it's a traffic limit (ends with T/G/M)
                    if [[ "$next_arg" =~ ^[0-9]+[TGM]$ ]]; then
                        _traffic_limit="$next_arg"
                        # Get reset day if provided
                        if ((i+2 < ${#_args[@]})); then
                            local day_arg="${_args[$((i+2))]}"
                            if [[ "$day_arg" =~ ^[0-9]+$ ]] && [ "$day_arg" -ge 1 ] && [ "$day_arg" -le 31 ]; then
                                _reset_day="$day_arg"
                            fi
                        fi
                        # Get traffic mode if provided
                        if ((i+3 < ${#_args[@]})); then
                            local mode_arg="${_args[$((i+3))]}"
                            local mode_lower="${mode_arg,,}"
                            case "$mode_lower" in
                                upload|download|both)
                                    _traffic_mode="$mode_lower"
                                    ;;
                            esac
                        fi
                    fi
                fi
                return
                ;;
            traffic-*|-traffic-*)
                # Format: TRAFFIC1T or -TRAFFIC1T-5 or -TRAFFIC1T-5-upload
                local traffic_arg="${arg#traffic-}"
                traffic_arg="${traffic_arg#-traffic-}"
                # Extract limit, reset day, and optional traffic mode
                if [[ "$traffic_arg" =~ ^[0-9]+[TGM]-[0-9]+-(upload|download|both)$ ]]; then
                    _traffic_limit="${traffic_arg%%-*}"
                    local temp="${traffic_arg#*-}"
                    _reset_day="${temp%%-*}"
                    _traffic_mode="${temp##*-}"
                elif [[ "$traffic_arg" =~ ^[0-9]+[TGM]-[0-9]+$ ]]; then
                    _traffic_limit="${traffic_arg%-*}"
                    _reset_day="${traffic_arg##*-}"
                elif [[ "$traffic_arg" =~ ^[0-9]+[TGM]$ ]]; then
                    _traffic_limit="$traffic_arg"
                fi
                return
                ;;
        esac
    done
    return 0
}

# Parse command line arguments for NAT parameters
parse_nat_args() {
    local -n _nat_range=$1
    local -n _clear_nat=$2
    local _args=("$@")

    for ((i=0; i<${#_args[@]}; i++)); do
        local arg="${_args[$i]}"
        local arg_lower="${arg,,}"
        case "$arg_lower" in
            --clear-nat)
                _clear_nat=1
                return
                ;;
            traffic|-traffic)
                return
                ;;
            traffic-*|-traffic-*)
                return
                ;;
            nat|-nat)
                # Collect remaining args until next flag
                for ((j=i+1; j<${#_args[@]}; j++)); do
                    local next_arg="${_args[$j]}"
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
                # Validate NAT mappings immediately
                if [ -n "$_nat_range" ]; then
                    for mapping in $_nat_range; do
                        if ! validate_nat_mapping "$mapping"; then
                            echo ""
                            echo "Usage:"
                            echo "  ./install.sh [options]"
                            echo "  ./install.sh NAT port1-port2 [port3-port4 ...]"
                            echo "  ./install.sh --clear-nat"
                            echo ""
                            echo "Examples:"
                            echo "  ./install.sh"
                            echo "  ./install.sh NAT 1-2"
                            echo "  ./install.sh NAT 8080-80 9000-3000"
                            exit 1
                        fi
                    done
                fi
                return
                ;;
            nat-*|-nat-*)
                # Format: NAT8080-80 or -NAT8080-80
                _nat_range="${arg#nat-}"
                _nat_range="${_nat_range#-nat-}"
                # Validate NAT mapping immediately
                if [ -n "$_nat_range" ]; then
                    if ! validate_nat_mapping "$_nat_range"; then
                        echo ""
                        echo "Usage:"
                        echo "  ./install.sh [options]"
                        echo "  ./install.sh NAT port1-port2"
                        echo "  ./install.sh --clear-nat"
                        echo ""
                        echo "Examples:"
                        echo "  ./install.sh"
                        echo "  ./install.sh NAT 1-2"
                        exit 1
                    fi
                fi
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
        echo "Traffic Limit:"
        echo "  sysinfo TRAFFIC 1T     - Set monthly traffic limit (default: 1T, reset day: 1, mode: both)"
        echo "  sysinfo TRAFFIC 500G 15 - Set 500G limit, reset on 15th day"
        echo "  sysinfo TRAFFIC 500G upload - Set 500G upload-only limit (reset day: 1)"
        echo "  sysinfo TRAFFIC 500G download - Set 500G download-only limit (reset day: 1)"
        echo "  sysinfo TRAFFIC 500G 15 upload - Set 500G upload-only limit, reset on 15th"
        echo "  sysinfo TRAFFIC 500G upload 15 - Same as above (mode can come before reset day)"
        echo "  sysinfo --reset-traffic - Reset monthly traffic statistics"
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
    --reset-traffic)
        sudo rm -f /etc/sysinfo-traffic.json
        echo "Monthly traffic statistics reset"
        exit 0
        ;;
    traffic|-traffic)
        shift
        limit="$1"
        reset_day=1
        traffic_mode="both"

        # Check second parameter
        if [ -n "$2" ]; then
            param2="${2,,}"
            case "$param2" in
                upload|download|both)
                    # Second parameter is a traffic mode
                    traffic_mode="$param2"
                    # Check third parameter for reset day
                    if [ -n "$3" ] && [[ "$3" =~ ^[0-9]+$ ]] && [ "$3" -ge 1 ] && [ "$3" -le 31 ]; then
                        reset_day="$3"
                    fi
                    ;;
                *)
                    # Second parameter might be a reset day
                    if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 31 ]; then
                        reset_day="$2"
                        # Check third parameter for traffic mode
                        if [ -n "$3" ]; then
                            param3="${3,,}"
                            case "$param3" in
                                upload|download|both)
                                    traffic_mode="$param3"
                                    ;;
                            esac
                        fi
                    fi
                    ;;
            esac
        fi

        # Validate limit
        if [[ ! "$limit" =~ ^[0-9]+[TGM]$ ]]; then
            echo "Error: Invalid traffic limit format '$limit'"
            echo "Expected format: Number + Unit (T/G/M)"
            echo "  Examples: 1T, 500G, 100M"
            exit 1
        fi

        # Validate traffic mode
        case "$traffic_mode" in
            upload|download|both) ;;
            *)
                echo "Error: Invalid traffic mode '$traffic_mode' (must be: upload, download, or both)"
                exit 1
                ;;
        esac

        # Save config
        echo "{\"limit\":\"$limit\",\"reset_day\":$reset_day,\"traffic_mode\":\"$traffic_mode\"}" | sudo tee /etc/sysinfo-traffic >/dev/null
        # Reset traffic stats when limit changes
        sudo rm -f /etc/sysinfo-traffic.json
        case "$traffic_mode" in
            upload) mode_display="upload only" ;;
            download) mode_display="download only" ;;
            both) mode_display="bi-directional" ;;
        esac
        echo "Traffic limit: $limit per month ($mode_display), reset on day $reset_day"
        echo "Monthly traffic statistics reset"
        exit 0
        ;;
    traffic-*|-traffic-*)
        traffic_arg="${1#traffic-}"
        traffic_arg="${traffic_arg#-traffic-}"

        # Extract limit, reset day, and optional traffic mode
        if [[ "$traffic_arg" =~ ^[0-9]+[TGM]-[0-9]+-(upload|download|both)$ ]]; then
            limit="${traffic_arg%%-*}"
            local temp="${traffic_arg#*-}"
            reset_day="${temp%%-*}"
            traffic_mode="${temp##*-}"
        elif [[ "$traffic_arg" =~ ^[0-9]+[TGM]-[0-9]+$ ]]; then
            limit="${traffic_arg%-*}"
            reset_day="${traffic_arg##*-}"
            traffic_mode="both"
        elif [[ "$traffic_arg" =~ ^[0-9]+[TGM]$ ]]; then
            limit="$traffic_arg"
            reset_day=1
            traffic_mode="both"
        else
            echo "Error: Invalid traffic format '$1'"
            echo "Expected format: TRAFFIC<limit>[-reset_day][-mode]"
            echo "  Examples: TRAFFIC1T, TRAFFIC500G-15, TRAFFIC500G-15-upload"
            exit 1
        fi

        # Validate reset day
        if ! [[ "$reset_day" =~ ^[0-9]+$ ]] || [ "$reset_day" -lt 1 ] || [ "$reset_day" -gt 31 ]; then
            echo "Error: Invalid reset day '$reset_day' (must be 1-31)"
            exit 1
        fi

        # Validate traffic mode
        case "$traffic_mode" in
            upload|download|both) ;;
            *)
                echo "Error: Invalid traffic mode '$traffic_mode' (must be: upload, download, or both)"
                exit 1
                ;;
        esac

        # Save config
        echo "{\"limit\":\"$limit\",\"reset_day\":$reset_day,\"traffic_mode\":\"$traffic_mode\"}" | sudo tee /etc/sysinfo-traffic >/dev/null
        # Reset traffic stats when limit changes
        sudo rm -f /etc/sysinfo-traffic.json
        case "$traffic_mode" in
            upload) mode_display="upload only" ;;
            download) mode_display="download only" ;;
            both) mode_display="bi-directional" ;;
        esac
        echo "Traffic limit: $limit per month ($mode_display), reset on day $reset_day"
        echo "Monthly traffic statistics reset"
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

# Start monitoring with watch (use -t to avoid height truncation)
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
    echo "  sysinfo TRAFFIC 1T    - Set monthly traffic limit (default: 1T)"
    echo "  sysinfo --reset-traffic - Reset monthly traffic statistics"
    echo ""
    echo "Installation with NAT mappings:"
    echo "  ./install.sh NAT 1-2 2-3"
    echo ""
    echo "Installation with traffic limit:"
    echo "  ./install.sh TRAFFIC 1T"
    echo "  ./install.sh TRAFFIC 500G 15  (500G limit, reset on 15th)"
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

# Parse NAT and traffic arguments
NAT_RANGE=""
CLEAR_NAT=0
TRAFFIC_LIMIT="1T"
RESET_DAY=1
TRAFFIC_MODE="both"
parse_nat_args NAT_RANGE CLEAR_NAT "$@"
parse_traffic_args TRAFFIC_LIMIT RESET_DAY TRAFFIC_MODE "$@"

# Validate traffic limit
if ! validate_traffic_limit "$TRAFFIC_LIMIT"; then
    exit 1
fi

# Clean up old installation
echo "Cleaning up old installation..."
sudo rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh \
         /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main \
         /etc/sysinfo-lang /etc/sysinfo-nat
# Clean up net stats files for all users
sudo rm -f /var/tmp/sysinfo_net_stats_*

echo "Starting installation..."

# Handle NAT configuration (already validated in parse_nat_args)
if [ "$CLEAR_NAT" = "1" ]; then
    echo "NAT port mappings cleared"
elif [ -n "$NAT_RANGE" ]; then
    save_nat_mappings "$NAT_RANGE"
fi

# Handle traffic configuration
save_traffic_config "$TRAFFIC_LIMIT" "$RESET_DAY" "$TRAFFIC_MODE"

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
