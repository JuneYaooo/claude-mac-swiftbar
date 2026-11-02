# claude-mac-swiftbar

SwiftBar 菜单栏套件：**Claude 环境风险监控** + **网速/出口 IP 显示**。

| 菜单栏图标 | 插件 | 刷新 | 功能 |
|---|---|---|---|
| `🟢100` | `claude-risk.10m.sh` | 10 min | Claude 环境风险评分：7 项实时快探 + 一键 26 信号深度体检 |
| `↓41K ↑92K · IP` | `net.30s.sh` | 30 s | 实时网速（下行/上行）+ 出口 IP 及归属，纯 bash 零依赖 |

安装后两个图标都会出现在菜单栏。

```
🟢100  （点开）
├─ ✓ 出口国家: US
├─ ✓ Anthropic API: HTTP 401 (401=健康)
├─ ✓ 三路一致: 国内 38.244.1.210 / 国际 38.244.1.210 / 谷歌 38.244.1.210
├─ ✓ 时区匹配: 系统 America/Los_Angeles / 出口 America/Los_Angeles
├─ ✓ DNS: 1.1.1.1
├─ ✓ pf 防泄漏规则: 已加载
└─ ✓ sing-box: 运行中
```

## 图标含义与告警分级

| 图标 | 含义 |
|---|---|
| 🟢 | 全部正常 |
| 🟡 | 轻微问题（三路分流 / 时区漂移 / 国内 DNS），或单次远端探测波动「待确认」 |
| 🔴 | 严重问题：出口落入不支持地区 / API 不可达 / sing-box 挂 / pf 规则丢失 |

告警按**确定性分级**：

- **本地确定性故障**（sing-box 进程挂、pf 规则丢失）→ 立即 🔴，不防抖——这类故障会导致流量直连、真实 IP 暴露，是必须马上处理的真危险；
- **远端测量失败**（网络瞬断）→ 自动重试一次，单轮异常只显示 🟡 沿用上次健康分「待确认」，连续 2 轮失败才显示真实降分——避免网络瞬断误报。

## 快探项（claude-risk，每 10 分钟，约 2 秒）

出口国家（ip-api）/ Anthropic API 连通（401=健康）/ 三路出口一致（国内·国际·谷歌多端点）/ 时区匹配 / 系统 DNS / pf 防泄漏锚点 / sing-box 存活。

## 网速 + 出口 IP（net.30s.sh，每 30 秒）

菜单栏实时显示 `↓下行 ↑上行 · 出口IP`，纯 bash 实现（`netstat` 差分采样，无需任何第三方监控 App）。下拉含实时速率、IP 归属（国家·城市·ISP）、各物理网卡累计流量。IP 查询带 10 分钟缓存，双源兜底（icanhazip / ip.sb）。

## 深度体检（菜单内点击触发，约 40 秒）

完整运行 [zzusec/CheckClaude](https://github.com/zzusec/CheckClaude) 的 26 信号加权评分模型（含浏览器指纹、DNS 污染、出口稳定性等），报告写入 `~/Library/Application Support/CheckClaude/last-report.txt` 并弹系统通知。

## 安装

前置：macOS 12+ 与 [SwiftBar](https://github.com/swiftbar/SwiftBar)。

```bash
git clone https://github.com/JuneYaooo/claude-mac-swiftbar.git
cd claude-mac-swiftbar
bash install.sh            # 默认插件目录 ~/Documents/swiftbar
bash install.sh "/path/to/你的插件目录"   # 或显式指定
```

装完自动刷新 SwiftBar，菜单栏即出现评分图标。手动安装等价于：`swiftbar/claude-risk.10m.sh` 放入 SwiftBar 插件目录，`lib/` 下三个脚本放入 `~/CheckClaude/` 并 `chmod +x`。

> 若在终端直接跑 `claude-check.sh`（而非通过 SwiftBar），7 个浏览器信号按「未采集」中性计分，满分 94；真实浏览器实测口径为 100。这是检测方式的保留分，不是环境扣分。

## 配套环境（插件监控的对象）

本插件监控的是一台按 zzusec/CheckClaude 模型加固过的机器，当前架构：

- **sing-box TUN 全局**：所有流量（含国内）统一走美国住宅出口，消除三路分流；国内域名 DNS 经代理用 8.8.8.8 DoH 解析
- **pf 防泄漏**：阻断 STUN 直连出站（UDP+TCP 3478/5349/19302），堵死 WebRTC 真实 IP 泄漏
- **系统 DNS**：1.1.1.1 / 8.8.8.8（被 TUN 劫持进隧道）
- **时区/区域与出口对齐**：America/Los_Angeles + zh-Hans_US

加固方法见 zzusec/CheckClaude 的 `--fix` 流程或其 README。

## 免责声明

评分只反映本机环境指纹的矛盾，不是 Anthropic 官方判定，不构成账号安全保证。本工具不读取、不修改任何 Claude 账号凭据。

## 致谢

深度体检脚本与 26 信号评分模型来自 [zzusec/CheckClaude](https://github.com/zzusec/CheckClaude)（MIT License）。菜单栏插件为本仓库原创（MIT）。

## License

MIT
