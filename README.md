# sysinfo

A lightweight system status dashboard for Debian/Ubuntu SSH login.

[中文说明](README_zh.md)

## preview
![c447c317c140f367001.png](https://r2.baixiaosheng.de/2026/02/16/c447c317c140f367001.png)

## Features
- **SSH Banner**: Real-time stats upon login via `/etc/profile.d/`.
- **Live Monitor**: Shortcut command `sysinfo` for 1s refresh mode.
- **Network Speed**: Real-time network speed monitoring (RX/TX)
- **Dynamic Bars**: Visualized disk usage with color alerts.
- **Lightweight**: Minimal dependencies and fast execution.

## Quick Installation

1. Via baixiaosheng.de:
   ```bash
   bash <(curl -sSL baixiaosheng.de/sysinfo)
   ```

2. Via GitHub:
   ```bash
   curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash
   ```

3. Download and run:
   ```bash
   git clone https://github.com/jokerknight/sysinfo-cli.git
   cd sysinfo-cli
   ./install.sh
   ```

## Usage
- **Login**: Dashboard automatically appears when you SSH into the server.
- **Manual**: Type `sysinfo` to start live monitoring.
- **Quit**: Press `Ctrl+C` to exit live mode.

## Uninstall

1. Via baixiaosheng.de:
   ```bash
   bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
   ```

2. Via GitHub:
   ```bash
   curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/uninstall.sh | bash
   ```

3. Local script:
   ```bash
   cd sysinfo-cli
   ./uninstall.sh
   ```

## Files
- `sysinfo.sh`: The core logic script.
- `install.sh`: One-key installation script.
- `uninstall.sh`: One-key uninstall script.
