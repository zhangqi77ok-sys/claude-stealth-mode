# Claude Stealth Mode (Claude 免 TUN 终极防封隐身工具)

🚀 **专为 Windows 平台打造的 Claude / Claude Desktop 防区域检测与防封号终极自动化隐身工具。**

**无需开启虚拟网卡（TUN 模式），无需手动安装任何浏览器扩展或手动修改设置**，全脚本一键自动化解决 Claude 网页端与桌面端因国内真实 IP 泄露、WebRTC 穿透、时区与语言冲突导致的封号与区域拦截（*“App unavailable in your region”*）。

---

## 🌟 核心痛点与全自动化解决机制

| 泄漏与封号风险点 | 普通代理（未开 TUN）的表现 | 本工具全脚本自动化解决方案 |
| :--- | :--- | :--- |
| **WebRTC 穿透 (STUN UDP)** | 浏览器 WebRTC 绕过系统代理，直接向 STUN 发 UDP 包，泄露国内真实公网 IP (`111.x.x.x 异常`) | **双重物理封堵**：① 注入 Chrome/Edge 组策略 `WebRtcIPHandlingPolicy = disable_non_proxied_udp`；② 注入 Windows 内核级防火墙出站规则，物理拦截 STUN 探测端口 (3478, 19302~19309) 及浏览器直连 UDP，彻底消灭真实 IP 暴露。 |
| **浏览器语言暴露** | 浏览器默认发送 `zh-CN, zh`，触发 `语言不一致` 风控 | **组策略 + 偏好锁定**：注入 Chrome 组策略 `ForcedLanguages` (`en-US`, `en`) 与 `ApplicationLocaleValue` (`en-US`)，重写 Profile 偏好，强制浏览器向前端报告 `en-US, en`。 |
| **时区与地理指纹矛盾** | 代理节点在美国，系统时区与区域是 `Asia/Shanghai` | 自动切换并锁定系统时区为 **美国太平洋时间 (`Pacific Standard Time`)**，归属地设为美国 (`GeoID 244`)。 |
| **桌面端代码子进程裸连** | Claude 桌面端执行本地命令（PowerShell/Git/Node/Python）时绕过代理直连国内真实 IP | 注入用户级 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` 环境变量、广播 `WM_SETTINGCHANGE`，并自动注入 PowerShell Profile，堵死所有子进程。 |
| **设备硬件指纹关联** | Claude 桌面端本地写入 `ant-did` 与封禁历史绑定 | 自动扫描并抹除 `ant-did`、`ant-device-registry.json` 及沙箱临时文件，恢复干净设备状态。 |

---

## 📁 仓库结构

```text
├── Enable-ClaudeStealth.ps1    # 【一键开启】防检测隐身模式（全自动申请权限、下发策略与防火墙）
├── Disable-ClaudeStealth.ps1   # 【一键还原】恢复中国标准时间、中文语言、默认防火墙与网络设置
├── LICENSE                     # 开源许可证 (MIT)
└── README.md                   # 项目说明文档
```

---

## 🚀 快速使用

### 1. 开启隐身模式

直接右键 `Enable-ClaudeStealth.ps1` 选择 **“使用 PowerShell 运行”**（或在终端中运行）：

```powershell
powershell -ExecutionPolicy Bypass -File .\Enable-ClaudeStealth.ps1
```

*默认代理端口为 `7897`（Clash Verge 默认混合端口）。若使用其他端口，可通过参数指定：*
```powershell
powershell -ExecutionPolicy Bypass -File .\Enable-ClaudeStealth.ps1 -ProxyPort 7890
```

> **自动化全流程说明：**
> 1. **权限自提**：脚本自动申请 UAC 管理员权限，确保系统防火墙和企业组策略 100% 写入成功；
> 2. **环境注入**：自动解决 PowerShell 执行策略（`RemoteSigned`），注入 CLI 代理环境变量与 PowerShell 启动 Profile；
> 3. **系统伪装**：切换并锁定美国太平洋时区与 GeoID；
> 4. **WebRTC 防火墙拦截**：下发组策略并注入 Windows 防火墙规则，物理隔离 STUN UDP 探测；
> 5. **语言锁定**：强制下发 `en-US` 组策略并重写浏览器 Profile，消除 `zh-CN` 差异；
> 6. **设备重置**：抹除 Claude 历史硬件指纹与沙箱残留；
> 7. **自动验收**：自动拉起 Chrome 访问 [https://ip.net.coffee/claude/](https://ip.net.coffee/claude/) 供您实时查看全绿通过效果！

### 2. 恢复日常工作模式

当您用完 Claude，需要恢复常规中国时区（UTC+8）、中文语言与日常办公环境时，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-ClaudeStealth.ps1
```

所有防火墙规则、组策略、代理环境变量与时区均会瞬间无痕复原。

---

## 🛡️ [ip.net.coffee/claude/](https://ip.net.coffee/claude/) 验收标准

运行脚本后，打开检测页应达到的状态：

| 检测项 | 理想安全状态 | 说明 |
| :--- | :--- | :--- |
| **CLAUDE 可用性检测** | 🟢 `全部服务正常` | 代理节点与 Claude 连通性良好 |
| **DNS 泄露检测** | 🟢 `未检测到泄露` | DNS 出口与代理节点所在国一致 |
| **WEBRTC UDP 泄露检测** | 🟢 `未检测到泄露` 或 `WebRTC 已禁用或无泄露` | 111.x 真实国内 IP 彻底消失 |
| **设备信息 / 时区** | 🟢 `时区一致 America/Los_Angeles` | 时区与出口 IP 匹配 |
| **设备信息 / 语言** | 🟢 `语言一致 en-US, en` | 首选语言为英语，不再提示语言不一致 |

---

## ⚖️ 免责声明 (Disclaimer)

本项目仅供网络协议安全测试、WebRTC 防泄漏研究与个人技术交流使用。请遵守当地法律法规以及相关平台的服务条款。
