#!/bin/bash

# Run command as root (directly if already root, otherwise with non-interactive sudo)
run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

# Dedicated IFB device for download shaping (ingress redirect)
SYSINFO_IFB_DEV="ifb_sysinfo0"

# ============================================
# CLI Command Parser
# ============================================
# Supports flexible command formats:
#   sysinfo                          - Display system info
#   sysinfo [N]                      - Display with N seconds refresh
#   sysinfo --nat port1-port2 ...    - Set NAT mappings
#   sysinfo --traffic limit [day] [mode] - Set traffic limit
#   sysinfo --limit [enable|disable] [threshold] [rate] - Configure throttling (TC-based)
#   (legacy) --rate N is reserved and not used by installer anymore

normalize_traffic_limit() {
    local raw="${1^^}"
    raw="${raw// /}"

    if [[ "$raw" =~ ^UNLIMIT$|^\\-1$ ]]; then
        echo "UNLIMITED"
        return 0
    fi

    if [[ "$raw" =~ ^([0-9]+\.?[0-9]*)([TGM])B?$ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        return 0
    fi

    return 1
}

# Merge traffic config JSON safely (prefer jq, fallback to minimal valid JSON)
merge_traffic_config_json() {
    local current_json="$1"
    local limit="$2"
    local reset_day="$3"
    local mode="$4"

    if command -v jq >/dev/null 2>&1; then
        echo "$current_json" | jq -c \
            --arg limit "$limit" \
            --argjson reset_day "$reset_day" \
            --arg mode "$mode" \
            '. + {limit:$limit, reset_day:$reset_day, traffic_mode:$mode}' 2>/dev/null && return 0
    fi

    # Fallback: return a minimal valid JSON object
    echo "{\"limit\":\"$limit\",\"reset_day\":$reset_day,\"traffic_mode\":\"$mode\"}"
}

# Merge throttle config JSON safely
merge_throttle_config_json() {
    local current_json="$1"
    local enabled="$2"
    local threshold="$3"
    local rate="$4"
    local force="$5"
    force=${force:-false}

    if command -v jq >/dev/null 2>&1; then
        echo "$current_json" | jq -c \
            --argjson enabled "$enabled" \
            --argjson threshold "$threshold" \
            --arg rate "$rate" \
            --argjson force "$force" \
            '. + {throttle_enabled:$enabled, throttle_threshold:$threshold, throttle_rate:$rate, force_throttle:$force}' 2>/dev/null && return 0
    fi

    # Fallback: keep at least a valid JSON subset
    echo "{\"throttle_enabled\":$enabled,\"throttle_threshold\":$threshold,\"throttle_rate\":\"$rate\",\"force_throttle\":$force}"
}

remove_active_tc_limit() {
    command -v tc >/dev/null 2>&1 || return 0

    local interfaces
    interfaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)
    [ -n "$interfaces" ] || return 0

    while read -r interface; do
        [ -n "$interface" ] || continue
        [ "$interface" = "lo" ] && continue

        # Check if HTB exists with our handle (1:)
        local root_qdisc
        root_qdisc=$(tc qdisc show dev "$interface" 2>/dev/null | awk '/qdisc htb/ {for(i=1;i<=NF;i++) if($i ~ /^1:$/) print $i}' | tr -d ':')
        if [ -n "$root_qdisc" ] && [ "$root_qdisc" = "1" ]; then
            run_privileged tc qdisc del dev "$interface" root >/dev/null 2>&1
        fi

        if tc qdisc show dev "$interface" 2>/dev/null | grep -q " ingress "; then
            run_privileged tc qdisc del dev "$interface" ingress >/dev/null 2>&1
        fi
    done <<< "$interfaces"

    if ip link show dev "$SYSINFO_IFB_DEV" >/dev/null 2>&1; then
        run_privileged tc qdisc del dev "$SYSINFO_IFB_DEV" root >/dev/null 2>&1
    fi
}

parse_command() {
    local args=("$@")
    local nat_mappings=()
    local traffic_limit=""
    local traffic_reset_day=""
    local traffic_mode=""
    local throttle_threshold=""
    local throttle_rate=""
    local throttle_action=""
    local throttle_force="true"
    local refresh_rate=""
    local i=0

    # Check for old-style commands first (backward compatibility)
    if [ ${#args[@]} -gt 0 ]; then
        local first_arg="${args[0]}"
        local first_lower="${first_arg,,}"
        case "$first_lower" in
            nat)
                # Old NAT command format
                handle_nat_command "${args[@]:1}"
                return 0
                ;;
            traffic)
                # Old TRAFFIC command format
                handle_traffic_command "${args[@]:1}"
                return 0
                ;;
            throttle)
                # Old THROTTLE command format
                handle_throttle_command "${args[@]:1}"
                return 0
                ;;
        esac
    fi

    # Parse arguments with flag-based approach
    while [ $i -lt ${#args[@]} ]; do
        local arg="${args[$i]}"
        local lower_arg="${arg,,}"

        case "$lower_arg" in
            --nat)
                # Collect following port mappings until next flag
                i=$((i + 1))
                while [ $i -lt ${#args[@]} ]; do
                    local next_arg="${args[$i]}"
                    # Stop if we hit another flag
                    [[ "$next_arg" == --* ]] && break
                    # Check if it's a valid port mapping
                    if [[ "$next_arg" == *"-"* ]]; then
                        local before_dash="${next_arg%%-*}"
                        local after_dash="${next_arg#*-}"
                        if [[ "$before_dash" =~ ^[0-9]+$ ]] && [[ "$after_dash" =~ ^[0-9]+$ ]]; then
                            nat_mappings+=("$before_dash-$after_dash")
                        fi
                    fi
                    i=$((i + 1))
                done
                continue
                ;;
            --traffic)
                # Collect following traffic options until next flag
                i=$((i + 1))
                while [ $i -lt ${#args[@]} ]; do
                    local next_arg="${args[$i]}"
                    local next_lower="${next_arg,,}"
                    # Stop if we hit another flag
                    [[ "$next_arg" == --* ]] && break
                    case "$next_lower" in
                        upload|download|both)
                            traffic_mode="$next_lower"
                            ;;
                        *)
                            if [[ "$next_arg" =~ ^[0-9]+$ ]] && [ "$next_arg" -le 31 ]; then
                                traffic_reset_day="$next_arg"
                            else
                                if normalized_limit=$(normalize_traffic_limit "$next_arg"); then
                                    traffic_limit="$normalized_limit"
                                    # Break after setting limit
                                    break
                                fi
                            fi
                            ;;
                    esac
                    i=$((i + 1))
                done
                continue
                ;;
            --limit)
                # Skip --limit if traffic is set to unlimit
                if [ "$traffic_limit" = "UNLIMITED" ]; then
                    echo "ℹ Traffic is set to UNLIMITED, ignoring --limit parameters"
                    # Skip all --limit parameters until next flag
                    i=$((i + 1))
                    while [ $i -lt ${#args[@]} ]; do
                        [[ "${args[$i]}" == --* ]] && break
                        i=$((i + 1))
                    done
                    continue
                fi
                # Collect following throttle options until next flag
                i=$((i + 1))
                while [ $i -lt ${#args[@]} ]; do
                    local next_arg="${args[$i]}"
                    local next_lower="${next_arg,,}"
                    # Stop if we hit another flag
                    [[ "$next_arg" == --* ]] && break
                    case "$next_lower" in
                        enable|on|true|start)
                            throttle_action="enable"
                            ;;
                        disable|off|false|stop)
                            throttle_action="disable"
                            ;;
                        *)
                            if [[ "$next_arg" =~ ^[0-9]+$ ]]; then
                                # For --limit, any number is a threshold (1-100)
                                throttle_threshold="$next_arg"
                            elif [[ "$next_arg" =~ ^[0-9]+[kmgb]?bps?$ ]]; then
                                throttle_rate="$next_arg"
                            fi
                            ;;
                    esac
                    i=$((i + 1))
                done
                continue
                ;;
            --rate)
                # Collect refresh rate
                i=$((i + 1))
                if [ $i -lt ${#args[@]} ]; then
                    local next_arg="${args[$i]}"
                    if [[ "$next_arg" =~ ^[0-9]+$ ]]; then
                        refresh_rate="$next_arg"
                    fi
                    i=$((i + 1))
                fi
                continue
                ;;
            --reset-traffic|--reset)
                reset_traffic
                exit 0
                ;;
            --clear-nat)
                run_privileged rm -f /etc/sysinfo-nat
                echo "NAT port mappings cleared"
                exit 0
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                # Unknown option, skip
                i=$((i + 1))
                ;;
        esac
    done

    # Apply NAT mappings
    if [ ${#nat_mappings[@]} -gt 0 ]; then
        local nat_str="${nat_mappings[*]}"
        printf '%s\n' "$nat_str" | run_privileged tee /etc/sysinfo-nat >/dev/null 2>&1
        echo "✓ NAT port mappings configured: $nat_str"
    fi

    # Apply traffic configuration
    if [ -n "$traffic_limit" ] || [ -n "$traffic_reset_day" ] || [ -n "$traffic_mode" ]; then
        local limit=${traffic_limit:-1T}
        local reset_day=${traffic_reset_day:-1}
        local mode=${traffic_mode:-both}

        CONFIG_FILE="/etc/sysinfo-traffic"
        CURRENT_CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{}')

        CURRENT_CONFIG=$(merge_traffic_config_json "$CURRENT_CONFIG" "$limit" "$reset_day" "$mode")

        # If limit is UNLIMITED, disable throttling
        if [ "$limit" = "UNLIMITED" ]; then
            CURRENT_CONFIG=$(echo "$CURRENT_CONFIG" | jq -c '.throttle_enabled = false | .force_throttle = false' 2>/dev/null || echo "$CURRENT_CONFIG")
        fi

        printf '%s\n' "$CURRENT_CONFIG" | run_privileged tee "$CONFIG_FILE" >/dev/null 2>&1
        echo "✓ Traffic limit configured: $limit (reset day: $reset_day, mode: $mode)"
    fi

    # Apply throttle configuration (only if not UNLIMITED)
    if [ -n "$throttle_action" ] || [ -n "$throttle_threshold" ] || [ -n "$throttle_rate" ]; then
        # Check if current limit is UNLIMITED, if so, set to default 1T
        if [ "$traffic_limit" = "UNLIMITED" ] || [ "$traffic_limit" = "" ]; then
            # Set default 1T when enabling throttling without explicit traffic limit
            local limit="1T"
            local reset_day=1
            local mode="both"

            CONFIG_FILE="/etc/sysinfo-traffic"
            CURRENT_CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{}')
            CURRENT_CONFIG=$(merge_traffic_config_json "$CURRENT_CONFIG" "$limit" "$reset_day" "$mode")
            traffic_limit="$limit"
            # Save the updated config
            printf '%s\n' "$CURRENT_CONFIG" | run_privileged tee "$CONFIG_FILE" >/dev/null 2>&1
            echo "✓ Traffic limit set to default: 1T (for throttling)"
        fi

        if [ "$traffic_limit" != "UNLIMITED" ]; then
            if [ -n "$throttle_action" ] || [ -n "$throttle_threshold" ] || [ -n "$throttle_rate" ]; then
            CONFIG_FILE="/etc/sysinfo-traffic"
            CURRENT_CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{}')

            if [ "$throttle_action" = "disable" ]; then
                # Disable throttling
                if echo "$CURRENT_CONFIG" | grep -q '"throttle_enabled"'; then
                    CURRENT_CONFIG=$(echo "$CURRENT_CONFIG" | sed 's/"throttle_enabled":[^,}]*/"throttle_enabled":false/')
                    printf '%s\n' "$CURRENT_CONFIG" | run_privileged tee "$CONFIG_FILE" >/dev/null 2>&1
                fi
                remove_active_tc_limit
                echo "✓ Traffic throttling disabled"
        else
            # Enable or update throttling
            local threshold=${throttle_threshold:-95}
            local rate=${throttle_rate:-1mbps}
            local action=${throttle_action:-enable}
            local force=${throttle_force:-false}

            # Threshold 0 means immediate limiting

            # Validate rate >= 1mbps
            local rate_num rate_unit
            rate_num=$(echo "$rate" | sed -E 's/^([0-9]+).*/\1/')
            rate_unit=$(echo "$rate" | sed -E 's/^[0-9]+([kmg]?b?ps?)$/\1/')
            local rate_kbit=0
            case "$rate_unit" in
                Gbps|Gbit|Gb|gbps|gbit|gb) rate_kbit=$((rate_num * 1000 * 1000)) ;;
                Mbps|Mbit|Mb|mbps|mbit|mb) rate_kbit=$((rate_num * 1000)) ;;
                Kbps|Kbit|Kb|kbps|kbit|kb) rate_kbit=$rate_num ;;
                bps|bit|b) rate_kbit=$((rate_num / 1000)) ;;
                *) ;;
            esac
            if [ "$rate_kbit" -lt 1000 ]; then
                echo "✗ Error: Rate must be at least 1mbps (current: $rate)"
                echo "  Rates below 1mbps may cause network disconnection"
                return 1
            fi

            CURRENT_CONFIG=$(merge_throttle_config_json "$CURRENT_CONFIG" "true" "$threshold" "$rate" "$force")

            printf '%s\n' "$CURRENT_CONFIG" | run_privileged tee "$CONFIG_FILE" >/dev/null 2>&1

            # IMPORTANT: if a previous tc limit is already active (e.g. 10mbps),
            # clear runtime state so the next cycle re-applies with the new rate.
            remove_active_tc_limit
            rm -f /var/tmp/sysinfo_throttle_state >/dev/null 2>&1 || true

            if [ "$force" = "true" ]; then
                echo "✓ Traffic throttling $action: ${threshold}% limit at ${rate} (FORCE MODE)"
            else
                echo "✓ Traffic throttling $action: ${threshold}% limit at ${rate}"
            fi
        fi
        fi  # End of check for throttle variables
        fi  # End of check for UNLIMITED
    fi

    # Legacy compatibility: keep parsing --rate but installer no longer consumes runtime settings
    if [ -n "$refresh_rate" ]; then
        :
    fi

    # If nothing was configured, return 1 to display system info
    if [ ${#nat_mappings[@]} -eq 0 ] && [ -z "$traffic_limit" ] && [ -z "$traffic_reset_day" ] && [ -z "$traffic_mode" ] && [ -z "$throttle_action" ] && [ -z "$throttle_threshold" ] && [ -z "$throttle_rate" ] && [ -z "$refresh_rate" ]; then
        return 1
    fi

    return 0
}

# Handle TRAFFIC command with flexible arguments (backward compatibility)
handle_traffic_command() {
    local args=("$@")
    local limit=""
    local reset_day=""
    local mode=""
    local skip_remaining_args=false

    # Parse arguments (order doesn't matter)
    for arg in "${args[@]}"; do
        local lower_arg="${arg,,}"

        # Check for mode keywords
        case "$lower_arg" in
            upload|download|both)
                mode="$lower_arg"
                ;;
            --reset|--reset-traffic)
                reset_traffic
                exit 0
                ;;
            *)
                # Skip if we already found UNLIMITED
                if [ "$skip_remaining_args" = "true" ]; then
                    continue
                fi
                # Check if it's a number (reset_day only)
                if [[ "$arg" =~ ^[0-9]+$ ]] && [ "$arg" -le 31 ]; then
                    reset_day="$arg"
                # Check if it's a size format (e.g., 1T, 500G, 100M, or unlimit)
                elif normalized_limit=$(normalize_traffic_limit "$arg"); then
                    limit="$normalized_limit"
                    # If limit is UNLIMITED, stop processing further arguments
                    if [ "$limit" = "UNLIMITED" ]; then
                        skip_remaining_args=true
                    fi
                fi
                ;;
        esac
    done

    # Set defaults
    limit=${limit:-1T}
    reset_day=${reset_day:-1}
    mode=${mode:-both}

    # Save configuration
    CONFIG_FILE="/etc/sysinfo-traffic"
    CURRENT_CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{}')

    # Update or add traffic configuration
    CURRENT_CONFIG=$(merge_traffic_config_json "$CURRENT_CONFIG" "$limit" "$reset_day" "$mode")

    printf '%s\n' "$CURRENT_CONFIG" | run_privileged tee "$CONFIG_FILE" >/dev/null 2>&1
    echo "Traffic limit configured:"
    echo "  Limit: $limit"
    echo "  Reset day: $reset_day"
    echo "  Mode: $mode"
    exit 0
}

# Handle THROTTLE command with flexible arguments
handle_throttle_command() {
    local args=("$@")
    local threshold=""
    local rate=""
    local action=""

    # Parse arguments
    for arg in "${args[@]}"; do
        local lower_arg="${arg,,}"

        case "$lower_arg" in
            enable|on|true|start)
                action="enable"
                ;;
            disable|off|false|stop)
                action="disable"
                ;;
            *)
                # Check if it's a number (threshold)
                if [[ "$arg" =~ ^[0-9]+$ ]]; then
                    threshold="$arg"
                # Check if it's a rate format (e.g., 1mbps, 10mbps, 100kbps)
                elif [[ "$arg" =~ ^[0-9]+[kmgb]?bps?$ ]]; then
                    rate="$arg"
                fi
                ;;
        esac
    done

    CONFIG_FILE="/etc/sysinfo-traffic"
    CURRENT_CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{}')

    case "$action" in
        enable)
            # Enable throttling
            threshold=${threshold:-95}
            rate=${rate:-1mbps}

            # Update configuration
            if echo "$CURRENT_CONFIG" | grep -q '"throttle_enabled"'; then
                CURRENT_CONFIG=$(echo "$CURRENT_CONFIG" | sed 's/"throttle_enabled":[^,}]*/"throttle_enabled":true/' | sed "s/\"throttle_threshold\":[^,}]*/\"throttle_threshold\":$threshold/" | sed "s/\"throttle_rate\":[^,}]*/\"throttle_rate\":\"$rate\"/")
            else
                CURRENT_CONFIG=$(merge_throttle_config_json "$CURRENT_CONFIG" "true" "$threshold" "$rate" "false")
            fi

            printf '%s\n' "$CURRENT_CONFIG" | run_privileged tee "$CONFIG_FILE" >/dev/null 2>&1

            # Ensure existing active limit won't keep old rate after reconfiguration
            remove_active_tc_limit
            rm -f /var/tmp/sysinfo_throttle_state >/dev/null 2>&1 || true

            echo "Traffic throttling enabled:"
            echo "  Threshold: $threshold%"
            echo "  Rate limit: $rate (when threshold exceeded)"
            ;;
        disable)
            # Disable throttling
            if echo "$CURRENT_CONFIG" | grep -q '"throttle_enabled"'; then
                CURRENT_CONFIG=$(echo "$CURRENT_CONFIG" | sed 's/"throttle_enabled":[^,}]*/"throttle_enabled":false/')
                printf '%s\n' "$CURRENT_CONFIG" | run_privileged tee "$CONFIG_FILE" >/dev/null 2>&1
            fi
            remove_active_tc_limit
            echo "Traffic throttling disabled"
            ;;
        *)
            # If no action specified, just update threshold and rate
            if [ -n "$threshold" ] || [ -n "$rate" ]; then
                threshold=${threshold:-95}
                rate=${rate:-1mbps}

                if echo "$CURRENT_CONFIG" | grep -q '"throttle_enabled"'; then
                    CURRENT_CONFIG=$(echo "$CURRENT_CONFIG" | sed 's/"throttle_enabled":[^,}]*/"throttle_enabled":true/' | sed "s/\"throttle_threshold\":[^,}]*/\"throttle_threshold\":$threshold/" | sed "s/\"throttle_rate\":[^,}]*/\"throttle_rate\":\"$rate\"/")
                else
                    CURRENT_CONFIG=$(merge_throttle_config_json "$CURRENT_CONFIG" "true" "$threshold" "$rate" "false")
                fi

                printf '%s\n' "$CURRENT_CONFIG" | run_privileged tee "$CONFIG_FILE" >/dev/null 2>&1

                # Ensure existing active limit won't keep old rate after reconfiguration
                remove_active_tc_limit
                rm -f /var/tmp/sysinfo_throttle_state >/dev/null 2>&1 || true

                echo "Traffic throttling configured:"
                echo "  Threshold: $threshold%"
                echo "  Rate limit: $rate (when threshold exceeded)"
            else
                # Show current throttling status
                if echo "$CURRENT_CONFIG" | grep -q '"throttle_enabled":true'; then
                    local cur_threshold=$(echo "$CURRENT_CONFIG" | grep -o '"throttle_threshold":[0-9]*' | cut -d: -f2)
                    local cur_rate=$(echo "$CURRENT_CONFIG" | grep -o '"throttle_rate":"[^"]*"' | cut -d: -f2 | tr -d '"')
                    echo "Throttling enabled:"
                    echo "  Threshold: $cur_threshold%"
                    echo "  Rate limit: $cur_rate"
                else
                    echo "Throttling disabled or not configured"
                fi
            fi
            ;;
    esac
    exit 0
}

# Handle NAT command with flexible format (backward compatibility)
handle_nat_command() {
    local args=("$@")
    local mappings=()

    # Parse port mappings
    for arg in "${args[@]}"; do
        # Check if arg contains a dash (port mapping)
        if [[ "$arg" == *"-"* ]]; then
            # Split by dash
            local before_dash="${arg%%-*}"
            local after_dash="${arg#*-}"

            # Check if both parts are valid numbers
            if [[ "$before_dash" =~ ^[0-9]+$ ]] && [[ "$after_dash" =~ ^[0-9]+$ ]]; then
                mappings+=("$before_dash-$after_dash")
            fi
        fi
    done

    if [ ${#mappings[@]} -eq 0 ]; then
        echo "Error: No valid NAT mappings provided"
        echo "Usage: sysinfo --nat port1-port2 [port3-port4 ...]"
        echo "Example: sysinfo --nat 8080-80 9000-3000"
        exit 1
    fi

    # Join mappings with spaces
    local mappings_str="${mappings[*]}"

    # Save mappings
    printf '%s\n' "$mappings_str" | run_privileged tee /etc/sysinfo-nat >/dev/null 2>&1
    echo "NAT port mappings configured:"
    echo "  $mappings_str"
    exit 0
}

# Reset traffic statistics
reset_traffic() {
    local stats_file="/etc/sysinfo-traffic.json"
    local config_file="/etc/sysinfo-traffic"

    # Read traffic mode from config
    local traffic_mode=$(cat "$config_file" 2>/dev/null | grep -o '"traffic_mode":"[^"]*"' | cut -d: -f2 | tr -d '"')
    traffic_mode=${traffic_mode:-both}

    # Get current network values
    local reset_rx=0
    local reset_tx=0
    while read -r iface rx tx rest; do
        [ -n "$iface" ] || continue
        reset_rx=$((reset_rx + rx))
        reset_tx=$((reset_tx + tx))
    done < <(cat /proc/net/dev 2>/dev/null | grep -v "lo:" | grep -v "inter-|face" | tail -n +3 | tr -d '\r')

    # Reset stats
    printf '%s\n' "{\"start_time\":$(date +%s),\"rx_bytes\":0,\"tx_bytes\":0,\"last_rx\":$reset_rx,\"last_tx\":$reset_tx,\"traffic_mode\":\"$traffic_mode\",\"last_update\":$(date +%s)}" | run_privileged tee "$stats_file" >/dev/null 2>&1
    remove_active_tc_limit
    echo "Monthly traffic statistics reset"
}

# Show help
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
    echo "      Set traffic limit configuration"
    echo "      limit:  Traffic limit (e.g., 1T, 500G, 100M)"
    echo "      day:    Reset day (1-31, default: 1)"
    echo "      mode:   Mode (upload/download/both, default: both)"
    echo ""
    echo "  --limit [enable|disable] [threshold] [rate]"
    echo "      Configure traffic throttling (TC-based rate limiting)"
    echo "      enable:   Enable throttling (or: on, true, start)"
    echo "      disable:  Disable throttling (or: off, false, stop)"
    echo "      threshold: Traffic percentage (default: 95)"
    echo "      rate:     Speed limit (minimum: 1mbps, recommended: 1mbps)"
    echo "      NOTE: Throttle direction follows traffic mode (upload/download/both)"
    echo "      NOTE: Upload/Download share unified HTB + fq_codel shaping profile"
    echo "      NOTE: Download shaping uses IFB redirect + HTB for smoother low-rate control"
    echo "      NOTE: Works on gateway mode (ip_forward=1) by default"
    echo "      WARNING: Rate below 1mbps may cause network disconnection"
    echo ""
    echo "Examples:"
    echo "  # Set NAT port mapping only"
    echo "  sysinfo --nat 8080-80"
    echo ""
    echo "  # Set multiple NAT mappings"
    echo "  sysinfo --nat 1-2 3-5 8080-80"
    echo ""
    echo "  # Set traffic limit"
    echo "  sysinfo --traffic 1T"
    echo "  sysinfo --traffic 500G 15 upload"
    echo ""
    echo "  # Enable throttling"
    echo "  sysinfo --limit enable 95 1mbps"
    echo ""
    echo "  # Disable throttling"
    echo "  sysinfo --limit disable"
    echo ""
    echo "  # Set multiple configurations at once"
    echo "  sysinfo --nat 1-2 3-5 --traffic 500G upload --limit enable 95 1mbps"
    echo ""
    echo "Other Options:"
    echo "  --reset-traffic  Reset monthly traffic statistics"
    echo "  --clear-nat     Clear NAT port mappings"
    echo "  --help          Show this help message"
}

# Try to parse command first
if ! parse_command "$@"; then
    # No command, display system info
    :
fi

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
L_THROTTLE="Throttle Status"

THROTTLE_RUNTIME_STATUS="disabled"
THROTTLE_RUNTIME_DETAIL=""

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
    init_traffic_stats "$reset_rx" "$reset_tx" "$traffic_mode" | run_privileged tee "$stats_file" >/dev/null 2>&1
    remove_active_tc_limit
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
        init_traffic_stats "$init_rx" "$init_tx" | run_privileged tee "$stats_file" >/dev/null 2>&1
    fi

    # Read current stats
    local start_time=$(cat "$stats_file" 2>/dev/null | grep -o '"start_time":[0-9]*' | cut -d: -f2)
    start_time=${start_time:-$(date +%s)}
    local rx_bytes=$(cat "$stats_file" 2>/dev/null | grep -o '"rx_bytes":[0-9]*' | cut -d: -f2)
    rx_bytes=${rx_bytes:-0}
    local tx_bytes=$(cat "$stats_file" 2>/dev/null | grep -o '"tx_bytes":[0-9]*' | cut -d: -f2)
    tx_bytes=${tx_bytes:-0}

    # Check if month reset is needed
    # Reset when we have crossed the configured reset-day boundary since last update.
    local now_ts=$(date +%s)

    # Get last update time (fallback to start_time if not set)
    local last_update=$(cat "$stats_file" 2>/dev/null | grep -o '"last_update":[0-9]*' | cut -d: -f2)
    last_update=${last_update:-$start_time}

    local current_year_month=$(date +%Y-%m)
    local month_days=$(date -d "$current_year_month-01 +1 month -1 day" +%d)
    local effective_day=$reset_day
    if [ "$effective_day" -gt "$month_days" ]; then
        effective_day=$month_days
    fi

    local this_cycle_reset_ts
    this_cycle_reset_ts=$(date -d "$current_year_month-$effective_day 00:00:00" +%s)

    local cycle_reset_ts
    if [ "$now_ts" -ge "$this_cycle_reset_ts" ]; then
        cycle_reset_ts=$this_cycle_reset_ts
    else
        local prev_year_month
        prev_year_month=$(date -d "$current_year_month-01 -1 month" +%Y-%m)
        local prev_month_days
        prev_month_days=$(date -d "$prev_year_month-01 +1 month -1 day" +%d)
        local prev_effective_day=$reset_day
        if [ "$prev_effective_day" -gt "$prev_month_days" ]; then
            prev_effective_day=$prev_month_days
        fi
        cycle_reset_ts=$(date -d "$prev_year_month-$prev_effective_day 00:00:00" +%s)
    fi

    if [ "$last_update" -lt "$cycle_reset_ts" ]; then
        perform_reset
        return 0
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
    printf '%s\n' "{\"start_time\":$start_time,\"rx_bytes\":$rx_bytes,\"tx_bytes\":$tx_bytes,\"last_rx\":$current_rx,\"last_tx\":$current_tx,\"traffic_mode\":\"$traffic_mode\",\"last_update\":$current_time}" | run_privileged tee "$stats_file" >/dev/null 2>&1
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
        init_traffic_stats "$init_rx" "$init_tx" | run_privileged tee "$stats_file" >/dev/null 2>&1
    fi

    # Read config
    local limit=$(cat "$config_file" 2>/dev/null | grep -o '"limit":"[^"]*"' | cut -d: -f2 | tr -d '"')
    local has_limit="true"
    local limit_bytes=0

    # If no limit configured, treat as unlimited
    if [ -z "$limit" ]; then
        has_limit="false"
        limit="Unlimit"
    else
        # Convert limit to bytes - extract number and unit
        local normalized_limit
        if normalized_limit=$(normalize_traffic_limit "$limit"); then
            limit="$normalized_limit"
            local num="${limit%[TGM]}"
            local unit="${limit: -1}"
            # Use bc for decimal support
            if command -v bc >/dev/null 2>&1; then
                case "$unit" in
                    T) limit_bytes=$(echo "$num * 1024 * 1024 * 1024 * 1024 / 1" | bc -l | cut -d. -f1) ;;
                    G) limit_bytes=$(echo "$num * 1024 * 1024 * 1024 / 1" | bc -l | cut -d. -f1) ;;
                    M) limit_bytes=$(echo "$num * 1024 * 1024 / 1" | bc -l | cut -d. -f1) ;;
                    *) has_limit="false"; limit="Unlimit"; limit_bytes=0 ;;
                esac
            else
                # Fallback to awk if bc is not available
                case "$unit" in
                    T) limit_bytes=$(awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024 * 1024 * 1024}") ;;
                    G) limit_bytes=$(awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024 * 1024}") ;;
                    M) limit_bytes=$(awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024}") ;;
                    *) has_limit="false"; limit="Unlimit"; limit_bytes=0 ;;
                esac
            fi
        else
            has_limit="false"
            limit="Unlimit"
            limit_bytes=0
        fi

        # Verify limit_bytes was set
        if [ "$has_limit" = "true" ] && { [ -z "$limit_bytes" ] || [ "$limit_bytes" -eq 0 ]; }; then
            has_limit="false"
            limit="Unlimit"
            limit_bytes=0
        fi
    fi

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
    local perc=0
    if [ "$has_limit" = "true" ] && [ "$limit_bytes" -gt 0 ]; then
        perc=$(awk "BEGIN {printf \"%.0f\", ($total_bytes * 100) / $limit_bytes}")
        [ -z "$perc" ] && perc=0
        if [ "$perc" -gt 100 ]; then perc=100; fi
    fi

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

# --- Traffic Throttling Functions ---
# Convert rate string to tc format (e.g., 1mbps -> 1Mbit)
convert_rate_to_tc() {
    local rate="${1,,}"
    local num="${rate%%[a-z]*}"
    local unit="${rate#$num}"

    # Validate number part
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    case "$unit" in
        gbps|gbit|gb)
            echo "${num}Gbit"
            ;;
        mbps|mbit|mb)
            echo "${num}Mbit"
            ;;
        kbps|kbit|kb)
            echo "${num}Kbit"
            ;;
        bps|bit|b|"")
            echo "${num}bit"
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_ifb_device() {
    command -v ip >/dev/null 2>&1 || return 1

    # Best-effort module load
    run_privileged modprobe ifb numifbs=1 >/dev/null 2>&1 || true

    if ! ip link show dev "$SYSINFO_IFB_DEV" >/dev/null 2>&1; then
        run_privileged ip link add "$SYSINFO_IFB_DEV" type ifb >/dev/null 2>&1 || return 1
    fi

    run_privileged ip link set dev "$SYSINFO_IFB_DEV" up >/dev/null 2>&1 || return 1
    return 0
}

apply_download_limit_ifb() {
    local interface=$1
    local tc_rate=$2

    ensure_ifb_device || return 1

    # Reset old state to ensure idempotent behavior
    run_privileged tc qdisc del dev "$interface" ingress >/dev/null 2>&1 || true
    run_privileged tc qdisc del dev "$SYSINFO_IFB_DEV" root >/dev/null 2>&1 || true

    run_privileged tc qdisc add dev "$interface" handle ffff: ingress >/dev/null 2>&1 || return 1
    run_privileged tc filter del dev "$interface" parent ffff: >/dev/null 2>&1 || true
    run_privileged tc filter add dev "$interface" parent ffff: protocol all prio 1 u32 \
        match u32 0 0 action mirred egress redirect dev "$SYSINFO_IFB_DEV" >/dev/null 2>&1 || return 1

    apply_htb_fq_limit "$SYSINFO_IFB_DEV" "2" "20" "2:20" "220" "$tc_rate" >/dev/null 2>&1 || {
        run_privileged tc qdisc del dev "$SYSINFO_IFB_DEV" root >/dev/null 2>&1 || true
        run_privileged tc qdisc del dev "$interface" ingress >/dev/null 2>&1 || true
        return 1
    }

    return 0
}

# Apply HTB + fq_codel with the same shaping profile on a device.
# This helper is shared by upload (physical NIC) and download (IFB) to keep
# implementation consistent and easier to maintain.
apply_htb_fq_limit() {
    local dev=$1
    local root_handle=$2
    local default_class=$3
    local classid=$4
    local leaf_handle=$5
    local tc_rate=$6

    run_privileged tc qdisc add dev "$dev" root handle "${root_handle}:" htb default "$default_class" >/dev/null 2>&1 || return 1
    run_privileged tc class add dev "$dev" parent "${root_handle}:" classid "$classid" htb \
        rate "$tc_rate" burst 2M cburst 2M ceil "$tc_rate" prio 0 >/dev/null 2>&1 || return 1

    run_privileged tc qdisc replace dev "$dev" parent "$classid" handle "${leaf_handle}:" fq_codel >/dev/null 2>&1 || {
        run_privileged tc qdisc del dev "$dev" root >/dev/null 2>&1 || true
        return 1
    }

    return 0
}

# Safety guard: avoid tc shaping on router/gateway nodes.
# On gateway devices, changing root qdisc may disrupt forwarding and SSH.
is_gateway_mode() {
    local ipf
    ipf=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    [ "$ipf" = "1" ] && return 0
    return 1
}

# Detect default egress interface
get_default_interface() {
    local iface

    iface=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')
    if [ -n "$iface" ]; then
        echo "$iface"
        return 0
    fi

    iface=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')
    if [ -n "$iface" ]; then
        echo "$iface"
        return 0
    fi

    return 1
}

# Collect candidate interfaces for shaping (use default route interface only)
get_limit_interfaces() {
    local iface

    is_safe_physical_iface() {
        local ifn="$1"
        [ -n "$ifn" ] || return 1
        case "$ifn" in
            lo|docker*|br*|veth*|virbr*|tailscale*|wg*|tun*|tap*|Meta*)
                return 1
                ;;
            en*|eth*)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }

    # 1) Prefer default route interface only when it's a safe physical NIC.
    iface=$(get_default_interface)
    if is_safe_physical_iface "$iface"; then
        echo "$iface"
        return 0
    fi

    # 2) Fallback: first UP physical NIC.
    iface=$(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1 | grep -E '^(en|eth)' | head -n1)
    if is_safe_physical_iface "$iface"; then
        echo "$iface"
        return 0
    fi

    # No safe interface found -> do not apply shaping.
    return 1
}

apply_rate_limit_all() {
    local rate=$1
    local mode=${2:-both}
    local force=${3:-false}
    local ok_ifaces=""

    while read -r iface; do
        [ -n "$iface" ] || continue
        if apply_rate_limit "$iface" "$rate" "$mode" "$force"; then
            ok_ifaces+="$iface "
        fi
    done < <(get_limit_interfaces)

    if [ -n "$ok_ifaces" ]; then
        echo "$ok_ifaces" | xargs
        return 0
    fi

    return 1
}

remove_rate_limit_all() {
    local mode=${1:-both}
    local ok_ifaces=""

    while read -r iface; do
        [ -n "$iface" ] || continue
        if remove_rate_limit "$iface" "$mode"; then
            ok_ifaces+="$iface "
        fi
    done < <(get_limit_interfaces)

    if [ -n "$ok_ifaces" ]; then
        echo "$ok_ifaces" | xargs
        return 0
    fi

    return 1
}

# Apply rate limiting using tc (traffic control)
# Supports upload/download/both:
# - upload: HTB + fq_codel
# - download: IFB redirect + HTB + fq_codel
apply_rate_limit() {
    local interface=$1
    local rate=$2
    local mode=${3:-both}
    local force=${4:-false}

    # Hard safety stop for router/gateway hosts (unless force is enabled)
    if is_gateway_mode && [ "$force" != "true" ]; then
        return 2
    fi

    command -v tc >/dev/null 2>&1 || return 1
    ip link show dev "$interface" >/dev/null 2>&1 || return 1

    local tc_rate
    tc_rate=$(convert_rate_to_tc "$rate") || return 1

    local apply_upload="false"
    local apply_download="false"
    case "$mode" in
        upload) apply_upload="true" ;;
        download) apply_download="true" ;;
        both|*) apply_upload="true"; apply_download="true" ;;
    esac

    # Fail-safe: extremely low rates can make SSH/session appear disconnected.
    # Reject too-small limits to avoid accidental "network outage" experience.
    local tc_rate_num tc_rate_unit tc_rate_kbit
    tc_rate_num=$(echo "$tc_rate" | sed -E 's/^([0-9]+).*/\1/')
    tc_rate_unit=$(echo "$tc_rate" | sed -E 's/^[0-9]+([A-Za-z]+)$/\1/')
    case "$tc_rate_unit" in
        Gbit) tc_rate_kbit=$((tc_rate_num * 1000 * 1000)) ;;
        Mbit) tc_rate_kbit=$((tc_rate_num * 1000)) ;;
        Kbit) tc_rate_kbit=$tc_rate_num ;;
        bit) tc_rate_kbit=$((tc_rate_num / 1000)) ;;
        *) return 1 ;;
    esac
    if [ "$tc_rate_kbit" -lt 64 ]; then
        return 3
    fi

    # Check if already rate limited (avoid re-applying upload HTB)
    local already_limited=false
    if [ "$apply_upload" = "true" ] && tc qdisc show dev "$interface" 2>/dev/null | grep -q " htb "; then
        already_limited=true
        # Check if rate needs update - delete existing HTB to reapply with new rate
        local existing_class_rate
        existing_class_rate=$(tc class show dev "$interface" 2>/dev/null | grep "htb" | grep -oP 'rate \K[0-9]+[KMG]?bit' || echo "")
        if [ -n "$existing_class_rate" ]; then
            local existing_rate_kbit
            existing_rate_kbit=$(echo "$existing_class_rate" | sed -E 's/^([0-9]+).*/\1/')
            local existing_unit
            existing_unit=$(echo "$existing_class_rate" | sed -E 's/^[0-9]+([KMG]?bit)$/\1/')
            case "$existing_unit" in
                Gbit) existing_rate_kbit=$((existing_rate_kbit * 1000 * 1000)) ;;
                Mbit) existing_rate_kbit=$((existing_rate_kbit * 1000)) ;;
                Kbit) ;;
                bit) existing_rate_kbit=$((existing_rate_kbit / 1000)) ;;
            esac
            if [ "$existing_rate_kbit" -eq "$tc_rate_kbit" ]; then
                # Ensure low-latency leaf qdisc exists on our shaped class.
                # Use replace to be idempotent (older installs may miss this).
                run_privileged tc qdisc replace dev "$interface" parent 1:10 handle 110: fq_codel >/dev/null 2>&1 || true
                already_limited=true
            else
                run_privileged tc qdisc del dev "$interface" root >/dev/null 2>&1
                already_limited=false
            fi
        fi
    fi

    # CRITICAL FIX: Use HTB (Hierarchical Token Bucket) for upload shaping
    if [ "$apply_upload" = "true" ] && [ "$already_limited" = false ]; then
        # Never delete unknown root qdisc: that can disrupt connectivity.
        # Only proceed when root qdisc is known-safe/default.
        local current_qdisc
        current_qdisc=$(tc qdisc show dev "$interface" 2>/dev/null | grep -o "qdisc [a-z]*" | head -1 | awk '{print $2}')
        case "$current_qdisc" in
            ""|fq|fq_codel|pfifo_fast|noqueue)
                # Upload shaping now uses the same HTB+fq helper as IFB download shaping.
                apply_htb_fq_limit "$interface" "1" "10" "1:10" "110" "$tc_rate" >/dev/null 2>&1 || return 1
                ;;
            htb)
                already_limited=true
                ;;
            *)
                return 4
                ;;
        esac
    fi

    # Apply download limit via IFB redirect + HTB shaping.
    if [ "$apply_download" = "true" ]; then
        apply_download_limit_ifb "$interface" "$tc_rate" || return 1
    fi

    # Verify result by selected mode
    local verify_ok="true"
    if [ "$apply_upload" = "true" ] && ! tc qdisc show dev "$interface" 2>/dev/null | grep -q " htb "; then
        verify_ok="false"
    fi
    if [ "$apply_download" = "true" ] && ! tc qdisc show dev "$interface" 2>/dev/null | grep -q " ingress "; then
        verify_ok="false"
    fi

    if [ "$verify_ok" = "true" ] && [ "$apply_download" = "true" ]; then
        if ! tc qdisc show dev "$SYSINFO_IFB_DEV" 2>/dev/null | grep -q " htb "; then
            verify_ok="false"
        fi
    fi

    if [ "$verify_ok" = "true" ]; then
        return 0
    fi

    return 1
}

# Remove rate limiting
remove_rate_limit() {
    local interface=$1
    local mode=${2:-both}

    command -v tc >/dev/null 2>&1 || return 1
    ip link show dev "$interface" >/dev/null 2>&1 || return 1

    if [ "$mode" = "upload" ] || [ "$mode" = "both" ]; then
        # Check if HTB exists with our handle (1:)
        local root_qdisc
        root_qdisc=$(tc qdisc show dev "$interface" 2>/dev/null | awk '/qdisc htb/ {for(i=1;i<=NF;i++) if($i ~ /^1:$/) print $i}' | tr -d ':')
        if [ -n "$root_qdisc" ]; then
            # Only delete if it's our HTB (handle 1:)
            if [ "$root_qdisc" = "1" ]; then
                run_privileged tc qdisc del dev "$interface" root >/dev/null 2>&1
            fi
        fi
    fi

    if [ "$mode" = "download" ] || [ "$mode" = "both" ]; then
        if tc qdisc show dev "$interface" 2>/dev/null | grep -q " ingress "; then
            run_privileged tc qdisc del dev "$interface" ingress >/dev/null 2>&1
        fi
        if ip link show dev "$SYSINFO_IFB_DEV" >/dev/null 2>&1; then
            run_privileged tc qdisc del dev "$SYSINFO_IFB_DEV" root >/dev/null 2>&1
        fi
    fi

    return 0
}

# Check and apply traffic limit based on usage
# CRITICAL: This function is called frequently (every 1s in watch mode)
# We must avoid repeated tc operations that cause network instability
check_and_apply_limit() {
    local perc=$1
    local config_file="/etc/sysinfo-traffic"
    local state_file="/var/tmp/sysinfo_throttle_state"

    THROTTLE_RUNTIME_STATUS="disabled"
    THROTTLE_RUNTIME_DETAIL=""

    # Sync state file with actual tc status on startup
    local current_state=""
    if [ -f "$state_file" ]; then
        current_state=$(cat "$state_file" 2>/dev/null)
    fi

    # Check if tc actually has active limit applied on any interface
    # (upload via HTB and/or download via ingress)
    local actual_limited=false
    local interfaces
    interfaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)
    while read -r iface; do
        [ -n "$iface" ] || continue
        if tc qdisc show dev "$iface" 2>/dev/null | grep -q " htb "; then
            actual_limited=true
            break
        fi
        if tc qdisc show dev "$iface" 2>/dev/null | grep -q " ingress "; then
            actual_limited=true
            break
        fi
    done <<< "$interfaces"

    # Fix state file if it doesn't match reality
    if [ "$current_state" = "limited" ] && [ "$actual_limited" = false ]; then
        echo "ready" > "$state_file" 2>/dev/null
        current_state="ready"
    elif [ "$current_state" = "ready" ] && [ "$actual_limited" = true ]; then
        echo "limited" > "$state_file" 2>/dev/null
        current_state="limited"
    elif [ "$current_state" = "" ] && [ "$actual_limited" = true ]; then
        echo "limited" > "$state_file" 2>/dev/null
        current_state="limited"
    elif [ "$current_state" = "" ] && [ "$actual_limited" = false ]; then
        echo "ready" > "$state_file" 2>/dev/null
        current_state="ready"
    fi

    # Read throttling config
    local throttle_enabled=$(cat "$config_file" 2>/dev/null | grep -o '"throttle_enabled":[^,}]*' | cut -d: -f2 | tr -d ' "')
    local throttle_threshold=$(cat "$config_file" 2>/dev/null | grep -o '"throttle_threshold":[0-9]*' | grep -o '[0-9]*')
    local throttle_rate=$(cat "$config_file" 2>/dev/null | grep -o '"throttle_rate":"[^"]*"' | cut -d'"' -f4)
    local traffic_mode=$(cat "$config_file" 2>/dev/null | grep -o '"traffic_mode":"[^"]*"' | cut -d'"' -f4)
    local force_throttle=$(cat "$config_file" 2>/dev/null | grep -o '"force_throttle":[^,}]*' | cut -d: -f2 | tr -d ' "')

    throttle_enabled=${throttle_enabled:-false}
    throttle_threshold=${throttle_threshold:-95}
    throttle_rate=${throttle_rate:-1mbps}
    traffic_mode=${traffic_mode:-both}
    force_throttle=${force_throttle:-false}

    case "$traffic_mode" in
        upload|download|both) ;;
        *) traffic_mode="both" ;;
    esac

    # Apply direction follows traffic_mode from config.
    local throttle_apply_mode="$traffic_mode"
    local apply_mode_display="$traffic_mode"

    # Read current state (limiting or not)
    local current_state=""
    if [ -f "$state_file" ]; then
        current_state=$(cat "$state_file" 2>/dev/null)
    fi

    # Check if throttling is enabled and threshold exceeded
    if [ "$throttle_enabled" = "true" ]; then
        if [ "$perc" -ge "$throttle_threshold" ]; then
            if is_gateway_mode && [ "$force_throttle" != "true" ]; then
                THROTTLE_RUNTIME_STATUS="error"
                THROTTLE_RUNTIME_DETAIL="gateway mode detected (ip_forward=1), skip tc for safety"
                return 1
            fi

            # Need to apply rate limiting - only if not already applied
            if [ "$current_state" != "limited" ]; then
                # Apply rate limiting on all candidate interfaces
                local applied_ifaces
                applied_ifaces=$(apply_rate_limit_all "$throttle_rate" "$throttle_apply_mode" "$force_throttle")
                if [ -n "$applied_ifaces" ]; then
                    echo "limited" > "$state_file" 2>/dev/null
                    THROTTLE_RUNTIME_STATUS="limited"
                    THROTTLE_RUNTIME_DETAIL="$applied_ifaces @ $throttle_rate ($apply_mode_display)"
                    return 0
                fi

                # Fail-safe rollback: if applying limit fails, ensure no leftover qdisc
                # changes remain that could hurt connectivity.
                remove_active_tc_limit
                rm -f "$state_file" 2>/dev/null
                THROTTLE_RUNTIME_STATUS="error"
                THROTTLE_RUNTIME_DETAIL="apply failed on all interfaces (need tc + root/sudo -n)"
                return 1
            fi

            # Already limited, just report status
            THROTTLE_RUNTIME_STATUS="limited"
            THROTTLE_RUNTIME_DETAIL="active ($apply_mode_display)"
            return 0
        else
            # Need to remove rate limiting - only if currently applied
            if [ "$current_state" = "limited" ]; then
                local cleared_ifaces
                cleared_ifaces=$(remove_rate_limit_all "$throttle_apply_mode")
                if [ -n "$cleared_ifaces" ]; then
                    echo "ready" > "$state_file" 2>/dev/null
                    THROTTLE_RUNTIME_STATUS="ready"
                    THROTTLE_RUNTIME_DETAIL="$cleared_ifaces ($apply_mode_display)"
                    return 0
                fi

                THROTTLE_RUNTIME_STATUS="error"
                THROTTLE_RUNTIME_DETAIL="remove failed on all interfaces"
                return 1
            fi

            # Already not limited, just report status
            THROTTLE_RUNTIME_STATUS="ready"
            THROTTLE_RUNTIME_DETAIL="below threshold ($apply_mode_display)"
            return 0
        fi
    fi

    # Throttling disabled: ensure previous tc limit is removed
    if [ "$current_state" = "limited" ]; then
        remove_active_tc_limit
        rm -f "$state_file" 2>/dev/null
    fi
    THROTTLE_RUNTIME_STATUS="disabled"
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

    # Check and apply throttling - show current status
    config_file="/etc/sysinfo-traffic"
    throttle_enabled=$(cat "$config_file" 2>/dev/null | grep -o '"throttle_enabled":[^,}]*' | cut -d: -f2 | tr -d ' "')
    throttle_threshold=$(cat "$config_file" 2>/dev/null | grep -o '"throttle_threshold":[0-9]*' | grep -o '[0-9]*')
    throttle_rate=$(cat "$config_file" 2>/dev/null | grep -o '"throttle_rate":"[^"]*"' | cut -d'"' -f4)

    if [ "$throttle_enabled" = "true" ]; then
        # Check and apply rate limiting
        check_and_apply_limit "$TRAFFIC_PERC_NUM"

        # Show current throttle status
        # Translate mode for display
        mode_display=""
        case "$TRAFFIC_MODE" in
            "Upload Only") mode_display="↑" ;;
            "Download Only") mode_display="↓" ;;
            "Bi-directional") mode_display="↕" ;;
            *) mode_display="$TRAFFIC_MODE" ;;
        esac

        if [ "$THROTTLE_RUNTIME_STATUS" = "limited" ]; then
            printf "  %-14s : ${RED}Limit${NONE} (${throttle_threshold}%% at ${throttle_rate} ${mode_display}, ${THROTTLE_RUNTIME_DETAIL})\n" "$L_THROTTLE"
        elif [ "$THROTTLE_RUNTIME_STATUS" = "ready" ]; then
            printf "  %-14s : ${GREEN}Not Limit${NONE} (${throttle_threshold}%% at ${throttle_rate} ${mode_display}, iface ${THROTTLE_RUNTIME_DETAIL})\n" "$L_THROTTLE"
        elif [ "$THROTTLE_RUNTIME_STATUS" = "error" ]; then
            printf "  %-14s : ${YELLOW}Trigger Failed${NONE} (${THROTTLE_RUNTIME_DETAIL})\n" "$L_THROTTLE"
        else
            printf "  %-14s : ${GREEN}Disabled${NONE}\n" "$L_THROTTLE"
        fi
    fi
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
