# sysinfo

A lightweight system status dashboard for Debian/Ubuntu SSH login.

[中文说明](README_zh.md)

## Preview
![c447c317c140f367001.png](https://r2.baixiaosheng.de/2026/02/16/c447c317c140f367001.png)

## Features
- **SSH Banner**: Real-time stats upon login via `/etc/profile.d/`
- **Live Monitor**: Shortcut command `sysinfo` for real-time monitoring
- **Network Speed**: Real-time network speed monitoring with auto KB/s ↔ MB/s conversion
- **Traffic Statistics**: Monthly traffic tracking with configurable limits and counting modes
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

### Traffic Limit
```bash
# Set monthly traffic limit (default: 1T, reset day: 1, mode: bi-directional)
sysinfo TRAFFIC 1T

# Set limit with reset day
sysinfo TRAFFIC 500G 15        # 500G limit, reset on 15th day of each month

# Set limit with traffic mode (upload-only/download-only/bi-directional)
sysinfo TRAFFIC 500G upload    # Upload-only traffic counting
sysinfo TRAFFIC 500G download  # Download-only traffic counting

# Set limit with both reset day and mode (order flexible)
sysinfo TRAFFIC 500G 15 upload # 500G upload-only, reset on 15th
sysinfo TRAFFIC 500G upload 15 # Same as above

# Reset monthly traffic statistics
sysinfo --reset-traffic
```

**Note**: Traffic modes:
- `both` (default): Count both upload and download traffic
- `upload`: Count only upload traffic
- `download`: Count only download traffic

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
