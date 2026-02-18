# sysinfo

A lightweight system status dashboard for Debian/Ubuntu SSH login.

[中文说明](README_zh.md)

## Preview
![c447c317c140f367001.png](https://r2.baixiaosheng.de/2026/02/16/c447c317c140f367001.png)

## Features
- **SSH Banner**: Real-time stats upon login via `/etc/profile.d/`
- **Live Monitor**: Shortcut command `sysinfo` for real-time monitoring
- **Network Speed**: Real-time network speed monitoring with auto KB/s ↔ MB/s conversion
- **NAT Port Mapping**: Display and configure NAT port mappings
- **Dynamic Bars**: Visualized disk usage with color alerts
- **Lightweight**: Minimal dependencies and fast execution

## Quick Installation

### 1. Via baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo)
```

### 2. Via GitHub
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash
```

### 3. With NAT port mappings
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash -s -- NAT 1-2 2-3
```
**Note**: `1-2` format means `public_port->private_port`. Use `-` to avoid shell redirection issues.

### 4. Download and run
```bash
git clone https://github.com/jokerknight/sysinfo-cli.git
cd sysinfo-cli
./install.sh
```

## Usage

### Basic Commands
```bash
sysinfo              # Start real-time monitoring (1s refresh)
sysinfo 2            # Start with 2s refresh interval
sysinfo 5            # Start with 5s refresh interval
```

### NAT Port Mapping
```bash
# Set NAT port mappings (format: public_port-private_port)
sysinfo NAT 1-2              # Map port 1 (public) to port 2 (private)
sysinfo NAT 8080-80 9000-3000  # Set multiple mappings

# Clear all NAT mappings
sysinfo --clear-nat
```

### Installation with NAT
```bash
./install.sh NAT 1-2 2-3       # Install with NAT mappings
```

**Important**: NAT mappings use `-` format (e.g., `1-2`) instead of `->` to avoid shell redirection issues.

## Uninstall

### 1. Via baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
```

### 2. Via GitHub
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/uninstall.sh | bash
```

### 3. Local script
```bash
cd sysinfo-cli
./uninstall.sh
```

## Files
- `sysinfo.sh`: The core logic script
- `install.sh`: Installation script
- `uninstall.sh`: Uninstallation script
