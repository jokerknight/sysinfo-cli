# sysinfo

一个轻量级的系统状态监控面板，适用于 Debian/Ubuntu SSH 登录。

## 功能
- **SSH 登录显示**: 通过 `/etc/profile.d/` 自动在登录时显示系统信息
- **实时监控**: 快捷命令 `sysinfo` 以 1 秒刷新模式运行
- **动态进度条**: 可视化显示磁盘使用情况，带颜色警报
- **轻量级**: 最小的依赖和快速执行

## 快速安装

1. 通过 baixiaosheng.de 安装:
   ```bash
   bash <(curl -sSL baixiaosheng.de/sysinfo)
   ```

2. 通过 GitHub 安装:
   ```bash
   curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash
   ```

3. 下载后安装:
   ```bash
   git clone https://github.com/jokerknight/sysinfo-cli.git
   cd sysinfo-cli
   ./install.sh
   ```

## 使用方法
- **登录时**: 通过 SSH 登录到服务器时，仪表板会自动显示
- **手动执行**: 输入 `sysinfo` 启动实时监控
- **退出**: 按 `Ctrl+C` 退出实时模式

## 卸载

1. 通过 baixiaosheng.de 卸载:
   ```bash
   bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
   ```

2. 通过 GitHub 卸载:
   ```bash
   curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/uninstall.sh | bash
   ```

3. 下载后卸载:
   ```bash
   cd sysinfo-cli
   ./uninstall.sh
   ```

## 文件说明
- `sysinfo.sh`: 核心逻辑脚本
- `install.sh`: 一键安装脚本
- `uninstall.sh`: 一键卸载脚本
