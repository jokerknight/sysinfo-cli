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

### 3. Configure NAT port mappings after installation
```bash
sysinfo --nat 1-2 2-3
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

### Configuration Options (New Format)
The new CLI format uses flag-based options for better clarity and flexibility:

```bash
# NAT Port Mapping
sysinfo --nat 8080-80                    # Single mapping
sysinfo --nat 1-2 3-5 8080-80          # Multiple mappings

# Traffic Limit
sysinfo --traffic 1T                      # 1T monthly limit
sysinfo --traffic 500G 15                # 500G limit, reset on 15th
sysinfo --traffic 500G 15 upload         # 500G upload-only, reset on 15th

# Traffic Throttling
sysinfo --limit enable 95 1mbps          # Enable at 95% usage, limit to 1mbps
sysinfo --limit disable                    # Disable throttling
sysinfo --limit on 90 1mbps            # Use "on" keyword

# Combined Configuration (all at once)
sysinfo --nat 8080-80 9000-3000 --traffic 500G --limit enable 95 1mbps

# Clear NAT mappings
sysinfo --clear-nat

# Reset monthly traffic statistics
sysinfo --reset-traffic
```

**Configuration note**: `install.sh` only performs installation. Configure NAT/traffic/throttling after install via `sysinfo`.

**Reinstall note**: Re-running `install.sh` clears active runtime `tc/ifb` throttling state (runtime only) to avoid stale limits affecting new settings. After reinstall, run `sysinfo --nat/--traffic/--limit ...` again to apply your desired configuration.

### Legacy Commands (Still Supported)
For backward compatibility, the old command format is still available:

```bash
# NAT Port Mapping
sysinfo NAT 1-2
sysinfo NAT 8080-80 9000-3000

# Traffic Limit
sysinfo TRAFFIC 1T
sysinfo TRAFFIC 500G 15 upload

# Traffic Throttling
sysinfo THROTTLE enable 95 1mbps
sysinfo THROTTLE disable
```

**Important**: NAT mappings use `-` format (e.g., `1-2`) instead of `->` to avoid shell redirection issues.

### Traffic Parameters
- `limit`: Traffic limit (e.g., 1T, 500G, 100M)
- `day`: Reset day (1-31, default: 1)
- `mode`: Mode (upload/download/both, default: both)

**Traffic modes**:
- `both` (default): Count both upload and download traffic
- `upload`: Count only upload traffic
- `download`: Count only download traffic

### Throttling Parameters
- `action`: enable/disable/on/off/true/false/start/stop
- `threshold`: Traffic percentage (default: 95)
- `rate`: Speed limit (minimum: 1mbps, recommended: 1mbps)

**Note**: Throttling requires `tc` (Traffic Control) and root privileges (or passwordless sudo for `tc`).

**Implementation note (maintainability)**: Upload and download throttling now share the same HTB + fq_codel shaping profile. Download shaping applies the same profile via IFB redirect.

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
