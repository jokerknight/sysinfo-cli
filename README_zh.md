# sysinfo 

专为 Debian/Ubuntu 打造的轻量级 SSH 登录系统状态看板.

[English](./README.md)

## 功能特性
- **完美对齐**：针对终端中文字符宽度特别优化，冒号整齐划一。
- **双语支持**：根据系统语言环境（$LANG）自动切换中/英文。
- **登录自启**：集成至 `/etc/profile.d/`，SSH 登录即刻展现。
- **一键监控**：提供 `sysinfo` 指令，支持 1 秒频率动态刷新。
- **动态进度条**：根据磁盘占用率自动改变颜色（绿/黄/红）。

## 快速安装

**中文版本（推荐）：**
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo) -zh
```

**英文版本：**
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo)
```

**通过 GitHub 安装：**
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash -s -- -zh
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash
```

## 使用说明
- **自动显示**：SSH 登录后会自动显示。
- **实时监控**：在终端输入 `sysinfo` 进入实时刷新模式。
- **退出监控**：按下 `Ctrl + C`。

## 卸载
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
```

或通过 GitHub：
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/uninstall.sh | bash
```

## 文件说明
- `sysinfo.sh`: 核心监控脚本。
- `install.sh`: 一键安装脚本。
- `uninstall.sh`: 一键卸载脚本。