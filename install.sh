#!/bin/bash
GITHUB_RAW="https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main"
LANG_OPTION=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -zh|--zh|--chinese)
            LANG_OPTION="zh_CN.UTF-8"
            echo "Installing with Chinese language..."
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-zh|--zh|--chinese]"
            exit 1
            ;;
    esac
done

# Clean up old installation first
echo "Cleaning up old installation..."
sudo rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main /etc/sysinfo-lang

echo "Starting installation..."

# Download main script to /etc/profile.d/ (simple, direct approach)
if [ -n "$LANG_OPTION" ]; then
    # If -zh option, add export line at the beginning after shebang
    sudo bash -c "curl -sSL \"$GITHUB_RAW/sysinfo.sh\" | sed '1 a export SYSINFO_LANG=zh_CN' > /etc/profile.d/sysinfo.sh"
else
    sudo curl -sSL "$GITHUB_RAW/sysinfo.sh" -o /etc/profile.d/sysinfo.sh
fi
sudo chmod +x /etc/profile.d/sysinfo.sh

# Create 'sysinfo' command for real-time monitoring with watch
if [ -n "$LANG_OPTION" ]; then
    sudo bash -c "cat > /usr/local/bin/sysinfo <<EOF
#!/bin/bash
LANG=\"$LANG_OPTION\" watch -c -n 1 /etc/profile.d/sysinfo.sh
EOF"
else
    sudo bash -c "cat > /usr/local/bin/sysinfo <<EOF
#!/bin/bash
watch -c -n 1 /etc/profile.d/sysinfo.sh \"\$@\"
EOF"
fi
sudo chmod +x /usr/local/bin/sysinfo

echo "Done! Re-login to see dashboard, or type 'sysinfo' for real-time monitoring."