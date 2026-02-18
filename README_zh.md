# sysinfo

一个轻量级的系统状态监控面板，适用于 Debian/Ubuntu SSH 登录。

[English](README.md)

## 预览
![c447c317c140f367001.png](https://r2.baixiaosheng.de/2026/02/16/c447c317c140f367001.png)

## 功能
- **SSH 登录显示**: 通过 `/etc/profile.d/` 自动在登录时显示系统信息
- **实时监控**: 快捷命令 `sysinfo` 以 1 秒刷新模式运行
- **网络速度监控**: 实时监控网络下载/上传速度，自动转换 KB/s ↔ MB/s（超过 1024 KB/s 自动显示为 MB/s）
- **NAT 端口映射**: 显示和配置 NAT 端口映射
- **动态进度条**: 可视化显示磁盘使用情况，带颜色警报
- **轻量级**: 最小的依赖和快速执行

## 快速安装

### 1. 通过 baixiaosheng.de 安装
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo)
```

### 2. 通过 GitHub 安装
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash
```

### 3. 指定 NAT 端口映射
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash -s -- NAT 1-2 2-3
```
**注意**: `1-2` 格式表示 `公网端口->内网端口`。使用 `-` 而不是 `->` 避免重定向问题。

### 4. 下载后安装
```bash
git clone https://github.com/jokerknight/sysinfo-cli.git
cd sysinfo-cli
./install.sh
```

## 使用方法

### 基本命令
```bash
sysinfo              # 启动实时监控（1秒刷新）
sysinfo 2            # 以 2 秒间隔刷新
sysinfo 5            # 以 5 秒间隔刷新
```

### NAT 端口映射
```bash
# 设置 NAT 端口映射（格式：公网端口-内网端口）
sysinfo NAT 1-2              # 映射端口 1（公网）到端口 2（内网）
sysinfo NAT 8080-80 9000-3000  # 设置多个映射

# 清除所有 NAT 映射
sysinfo --clear-nat
```

### 安装时配置 NAT
```bash
./install.sh NAT 1-2 2-3       # 安装并配置 NAT 映射
```

**重要提示**: NAT 映射使用 `-` 格式（例如 `1-2`）而不是 `->`，以避免 Shell 重定向问题。

## 卸载

### 1. 通过 baixiaosheng.de 卸载
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
```

### 2. 通过 GitHub 卸载
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/uninstall.sh | bash
```

### 3. 本地脚本卸载
```bash
cd sysinfo-cli
./uninstall.sh
```

## 文件说明
- `sysinfo.sh`: 核心逻辑脚本
- `install.sh`: 安装脚本
- `uninstall.sh`: 卸载脚本
