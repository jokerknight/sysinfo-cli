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

echo "Starting installation..."

# Download main script to /etc/profile.d/
sudo curl -sSL "$GITHUB_RAW/sysinfo.sh" -o /etc/profile.d/sysinfo.sh
sudo chmod +x /etc/profile.d/sysinfo.sh

# Create shortcut command 'sysinfo' in /usr/local/bin/
if [ -n "$LANG_OPTION" ]; then
    sudo bash -c "cat > /usr/local/bin/sysinfo <<EOF
#!/bin/bash
LANG=\"$LANG_OPTION\" watch -c -n 1 /etc/profile.d/sysinfo.sh
EOF"
else
    sudo bash -c "cat > /usr/local/bin/sysinfo <<EOF
#!/bin/bash
watch -c -n 1 /etc/profile.d/sysinfo.sh
EOF"
fi
sudo chmod +x /usr/local/bin/sysinfo

echo "Done! Re-login or type 'sysinfo' to see the dashboard."