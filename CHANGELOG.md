# Changelog

本文档记录 `sysinfo-cli` 的重要更新。

## [Unreleased] - 2026-03-02

### 新增
- 新增了 流量统计 (上传/下载,  双向/单向 统计, 百分比显示, 流量重置)
- 新增了 限速设置 (单向/双向)
- 新增了 NAT 端口设置

Examples:
  sysinfo --nat 8080-80
  sysinfo --nat 1-2 3-5
  sysinfo --traffic 500G
  sysinfo --traffic 500G 15         # 500G, reset on 15th
  sysinfo --traffic 500G upload     # upload only
  sysinfo --traffic 500G 15 upload  # 500G, reset on 15th, upload
  sysinfo --limit enable 95 1mbps
  sysinfo --limit disable
  sysinfo --nat 1-2 --traffic 500G --limit enable 95 1mbps