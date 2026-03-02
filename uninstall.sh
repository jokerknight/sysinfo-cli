#!/bin/bash

run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

echo "Uninstalling sysinfo..."

# Remove installed scripts and commands
run_privileged rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh
run_privileged rm -f /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main

# Remove configuration and runtime state files
run_privileged rm -f /etc/sysinfo-lang /etc/sysinfo-nat /etc/sysinfo-traffic /etc/sysinfo-traffic.json
run_privileged rm -f /var/tmp/sysinfo_net_stats_* /var/tmp/sysinfo_throttle_state

echo "Done! sysinfo has been uninstalled."
