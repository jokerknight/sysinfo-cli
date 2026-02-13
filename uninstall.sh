#!/bin/bash

echo "Uninstalling sysinfo..."

# Remove the main script from profile.d
sudo rm -f /etc/profile.d/sysinfo.sh

# Remove the shortcut command
sudo rm -f /usr/local/bin/sysinfo

echo "Done! sysinfo has been uninstalled."
