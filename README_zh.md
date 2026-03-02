# sysinfo

一个轻量级的系统状态监控面板，适用于 Debian/Ubuntu SSH 登录。

[English](README.md)

## 预览
![c447c317c140f367001.png](https://r2.baixiaosheng.de/2026/02/16/c447c317c140f367001.png)

## 功能
- **SSH 登录显示**: 通过 `/etc/profile.d/` 自动在登录时显示系统信息
- **实时监控**: 快捷命令 `sysinfo` 以 1 秒刷新模式运行
- **网络速度监控**: 实时监控网络下载/上传速度，自动转换 KB/s ↔ MB/s（超过 1024 KB/s 自动显示为 MB/s）
- **流量统计**: 每月流量统计，支持配置流量限制和计数模式
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

### 3. 安装后配置 NAT 端口映射
```bash
sysinfo --nat 1-2 2-3
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

### 配置选项（新格式）
新的 CLI 格式使用基于标志的选项，更清晰、更灵活：

```bash
# NAT 端口映射
sysinfo --nat 8080-80                    # 单个映射
sysinfo --nat 1-2 3-5 8080-80          # 多个映射

# 流量限制
sysinfo --traffic 1T                      # 1T 月度限制
sysinfo --traffic 500G 15                # 500G 限制，15 号重置
sysinfo --traffic 500G 15 upload         # 500G 仅上传，15 号重置

# 流量超限限速
sysinfo --limit enable 95 1mbps          # 达到 95% 时限速 1mbps
sysinfo --limit disable                    # 禁用限速
sysinfo --limit on 90 1mbps            # 使用 on 关键字

# 组合配置（一次性设置所有）
sysinfo --nat 8080-80 9000-3000 --traffic 500G --limit enable 95 1mbps

# 清除 NAT 映射
sysinfo --clear-nat

# 重置月度流量统计
sysinfo --reset-traffic
```

**配置说明**：安装脚本仅负责安装。NAT、流量与限速等设置请在安装完成后通过 `sysinfo` 命令进行。

**重装说明**：重复执行 `install.sh` 时，会清理当前正在生效的 `tc/ifb` 运行时限速状态（仅运行时状态），以避免旧限速残留影响新配置。重装后请重新执行 `sysinfo --nat/--traffic/--limit ...` 完成配置。

### 旧版命令（仍支持）
为了向后兼容，旧版命令格式仍然可用：

```bash
# NAT 端口映射
sysinfo NAT 1-2
sysinfo NAT 8080-80 9000-3000

# 流量限制
sysinfo TRAFFIC 1T
sysinfo TRAFFIC 500G 15 upload

# 流量超限限速
sysinfo THROTTLE enable 95 1mbps
sysinfo THROTTLE disable
```

**重要提示**: NAT 映射使用 `-` 格式（例如 `1-2`）而不是 `->`，以避免 Shell 重定向问题。

### 流量参数说明
- `limit`: 流量限制（例如 1T, 500G, 100M）
- `day`: 重置日期（1-31，默认：1）
- `mode`: 模式（upload/download/both，默认：both）

**流量统计模式**：
- `both`（默认）：统计上传和下载双向流量
- `upload`：仅统计上传流量
- `download`：仅统计下载流量

### 限速参数说明
- `action`: enable/disable/on/off/true/false/start/stop
- `threshold`: 流量百分比（默认：95）
- `rate`: 限速值（最小 1mbps，推荐 1mbps）

**注意**: 限速功能需要 `tc` (Traffic Control) 工具支持，并且需要 root 权限（或为 `tc` 配置免密 sudo）。

**实现说明（便于维护）**：上传与下载限速现已统一为同一套 HTB + fq_codel 策略；其中下载方向通过 IFB 重定向后套用同样的整形配置。

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
