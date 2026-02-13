# sysinfo 

A lightweight system status dashboard for Debian/Ubuntu SSH login.

[中文说明](./README_zh.md)

## Features
- **Perfect Alignment**: Specialized formatting for CJK characters.
- **Bilingual**: Automatically switches between English and Chinese based on `$LANG`.
- **SSH Banner**: Real-time stats upon login via `/etc/profile.d/`.
- **Live Monitor**: Shortcut command `sysinfo` for 1s refresh mode.
- **Dynamic Bars**: Visualized disk usage with color alerts.

## Quick Installation

**English (default):**
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo)
```

**Chinese (中文):**
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo) -zh
```

Alternative (via GitHub):
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash -s -- -zh
```

## Usage
- **Login**: Dashboard automatically appears when you SSH into the server.
- **Manual**: Type `sysinfo` to start live monitoring.
- **Quit**: Press `Ctrl+C` to exit live mode.

## Uninstall
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
```

Or via GitHub:
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/uninstall.sh | bash
```

## Files
- `sysinfo.sh`: The core logic script.
- `install.sh`: One-key installation script.
- `uninstall.sh`: One-key uninstall script.