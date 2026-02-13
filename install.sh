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

# Check Chinese locale support if -zh option is used
check_chinese_support() {
    locale -a 2>/dev/null | grep -q -E 'zh_CN\.(utf8|UTF-8)'
}

install_chinese_locale() {
    local pkg_manager=""
    if command -v apt-get &> /dev/null; then
        pkg_manager="apt-get"
    elif command -v yum &> /dev/null; then
        pkg_manager="yum"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
    elif command -v pacman &> /dev/null; then
        pkg_manager="pacman"
    else
        echo "Cannot detect package manager. Please install Chinese locale manually."
        return 1
    fi

    case $pkg_manager in
        apt-get)
            sudo apt-get update && sudo apt-get install -y locales
            sudo sed -i 's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
            sudo locale-gen
            ;;
        yum|dnf)
            sudo $pkg_manager install -y glibc-langpack-zh
            ;;
        pacman)
            sudo pacman -S --noconfirm zh-cn
            ;;
    esac

    check_chinese_support
}

# Clean up old installation first
echo "Cleaning up old installation..."
sudo rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main /etc/sysinfo-lang

echo "Starting installation..."

# Download main script to /etc/profile.d/ (simple, direct approach)
sudo curl -sSL "$GITHUB_RAW/sysinfo.sh" -o /etc/profile.d/sysinfo.sh

# Modify the script if -zh option is specified
if [ -n "$LANG_OPTION" ]; then
    # Check if Chinese locale is installed
    if ! check_chinese_support; then
        echo "[WARNING] Chinese locale (zh_CN.UTF-8) is not installed."
        echo "Do you want to install it now? (y/n): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            if install_chinese_locale; then
                echo "Chinese locale installed successfully!"
            else
                echo "Failed to install Chinese locale. Installation will continue but Chinese may not display correctly."
            fi
        else
            echo "Skipping installation. Chinese may not display correctly."
        fi
    fi

    # Add export SYSINFO_LANG=zh_CN after the shebang line
    sudo awk 'NR==1{print; print "export SYSINFO_LANG=zh_CN"; next}1' /etc/profile.d/sysinfo.sh > /tmp/sysinfo.tmp && sudo mv /tmp/sysinfo.tmp /etc/profile.d/sysinfo.sh
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