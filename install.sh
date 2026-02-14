#!/bin/bash
GITHUB_RAW="https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main"

# Clean up old installation first
echo "Cleaning up old installation..."
sudo rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main /etc/sysinfo-lang

echo "Starting installation..."

# Download main script to /etc/profile.d/
sudo curl -sSL "$GITHUB_RAW/sysinfo.sh" -o /etc/profile.d/sysinfo.sh
sudo chmod +x /etc/profile.d/sysinfo.sh

# Create 'sysinfo' command for real-time monitoring with watch
sudo bash -c "cat > /usr/local/bin/sysinfo <<EOF
#!/bin/bash
watch -c -n 1 /etc/profile.d/sysinfo.sh \"\$@\"
EOF"
sudo chmod +x /usr/local/bin/sysinfo

echo "Done! Re-login to see dashboard, or type 'sysinfo' for real-time monitoring."