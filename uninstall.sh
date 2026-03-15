#!/bin/bash

run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

echo "Uninstalling sysinfo-cli..."

# Remove installed scripts
run_privileged rm -f /etc/profile.d/sysinfo.sh

# Remove sysinfo command
run_privileged rm -f /usr/local/bin/sysinfo

# Remove configuration files
run_privileged rm -f /etc/sysinfo-nat
run_privileged rm -f /etc/sysinfo-traffic /etc/sysinfo-traffic.json
run_privileged rm -f /var/tmp/sysinfo_net_stats_*
run_privileged rm -f /var/tmp/sysinfo_throttle_state

echo "Done! sysinfo-cli has been completely removed."

echo ""
echo "To reinstall, run:"
echo "  bash ./install.sh"
echo "Or for direct installation, run:"
echo "  sudo cp sysinfo.sh /etc/profile.d/sysinfo.sh"
echo "  sudo chmod +x /etc/profile.d/sysinfo.sh"
