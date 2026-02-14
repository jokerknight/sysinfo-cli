#!/bin/bash
GITHUB_RAW="https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main"

# Clean up old installation first
echo "Cleaning up old installation..."
sudo rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main /etc/sysinfo-lang

echo "Starting installation..."

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Copy main script to /etc/profile.d/
sudo cp "$SCRIPT_DIR/sysinfo.sh" /etc/profile.d/sysinfo.sh
sudo chmod +x /etc/profile.d/sysinfo.sh

# Create 'sysinfo' command for real-time monitoring using watch
sudo bash -c "cat > /usr/local/bin/sysinfo <<'EOF'
#!/bin/bash
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