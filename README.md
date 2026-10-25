# Claude Stealth Mode (Claude 免 TUN 终极防封隐身工具)

🚀 **专为 Windows 平台打造的 Claude / Claude Desktop 防区域检测、防网络泄露与防封号全自动生产级防护工具。**

**无需开启虚拟网卡（TUN 模式），无需手动安装任何浏览器扩展或手动修改复杂网络设置**，全脚本一键自动化解决 Claude 网页端与桌面端因国内真实 IP 泄露、WebRTC 穿透、IPv6 旁路、DNS 并发探测、时区与语言冲突导致的封号与区域拦截（*“App unavailable in your region”*）。

---

## 🌟 核心痛点与系统级防护机制

| 泄漏与封号风险点 | 普通代理（未开 TUN）的表现 | 本项目全脚本自动化解决方案 |
| :--- | :--- | :--- |
| **WebRTC 穿透 (STUN UDP)** | 浏览器 WebRTC 绕过系统代理向 STUN 发 UDP，泄露国内真实公网 IP (`111.x.x.x 异常`) | **双重物理封堵**：① 注入 Chrome/Edge 组策略 `WebRtcIPHandlingPolicy = disable_non_proxied_udp`；② 注入 Windows 内核级防火墙出站规则，物理拦截 STUN 探测端口 (3478, 19302~19309) 及浏览器直连 UDP，彻底消灭真实公网 IP 暴露。 |
| **IPv6 旁路直连泄露** | 国内宽带普遍支持 IPv6，代理软件未接管时系统通过双栈直接向目标服务器暴露国内 IPv6 | **协议栈禁用 + 防火墙阻断**：自动停用活动网卡 IPv6 绑定，并在防火墙下发全局 IPv6 出站阻断规则，彻底切断 IPv6 绕过代理的旁路通道。 |
| **DNS 智能多宿主泄露 (SMHNR)** | Windows 系统并发向国内物理网卡配置的运营商 DNS 发包探测 | **组策略封死**：注入 `DisableSmartNameResolution = 1`，彻底禁止 Windows 智能多宿主 DNS 并发解析，避免本地 DNS 记录留痕。 |
| **浏览器语言暴露** | 浏览器默认上报 `zh-CN, zh`，触发 Claude 前端 `语言不一致` 告警 | **组策略 + 偏好锁定**：注入 Chrome/Edge 组策略 `ForcedLanguages` (`en-US`, `en`) 与 `ApplicationLocaleValue` (`en-US`)，重写 Profile 偏好，强制浏览器向前端报告 `en-US, en`。 |
| **时区与地理指纹矛盾** | 代理节点在美国，系统时区与区域是 `Asia/Shanghai` | 自动切换并锁定系统时区为 **美国太平洋时间 (`Pacific Standard Time`)**，归属地设为美国 (`GeoID 244`)。 |
| **桌面端代码子进程裸连** | Claude 桌面端执行本地命令（PowerShell/Git/Node/Python）时绕过代理直连国内真实 IP | 注入用户级 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` 环境变量、广播 `WM_SETTINGCHANGE`，并自动注入 PowerShell Profile，堵死所有子进程。 |
| **设备硬件指纹关联** | Claude 桌面端本地写入 `ant-did` 与历史封号设备绑定 | 自动扫描并抹除 `ant-did`、`ant-device-registry.json` 及沙箱临时文件，恢复全新干净设备状态。 |
| **个人系统设置被破坏** | 还原时硬编码修改可能覆盖个人原本的时区或网卡配置 | **无损快照回滚**：开启时自动记录 `.stealth-snapshot.json` 快照，还原时精准恢复原有网卡、时区与网络状态。 |

---

## 📁 仓库结构

```text
├── Enable-ClaudeStealth.ps1    # 【一键开启】防检测隐身模式（全自动申请权限、下发策略、防火墙与自检）
├── Disable-ClaudeStealth.ps1   # 【一键还原】无损回滚系统时区、IPv6、DNS、默认防火墙与网络设置
├── Test-ClaudeStealth.ps1      # 【独立体检】全方位检测当前环境防泄漏健康度（命令行直接输出诊断报告）
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
> 2. **原值快照**：自动备份当前系统时区、GeoID 与 IPv6 适配器状态（生成 `.stealth-snapshot.json`）；
> 3. **IPv6 封堵**：禁用物理网卡 IPv6 绑定并添加防火墙全局 IPv6 出站阻断；
> 4. **DNS 锁定**：禁用 Windows 智能多宿主 DNS 解析 (SMHNR)；
> 5. **WebRTC 防火墙拦截**：下发组策略并注入 Windows 防火墙规则，物理隔离 STUN UDP 探测；
> 6. **语言锁定**：强制下发 `en-US` 组策略并重写浏览器 Profile，消除 `zh-CN` 差异；
> 7. **系统伪装**：切换并锁定美国太平洋时区与 GeoID；
> 8. **环境注入**：解决 PowerShell 执行策略（`RemoteSigned`），注入 CLI 代理环境变量与 PowerShell 启动 Profile；
> 9. **设备重置**：抹除 Claude 历史硬件指纹与沙箱残留；
> 10. **即时体检与验收**：自动运行内置体检脚本，并自动拉起 Chrome 访问 [https://ip.net.coffee/claude/](https://ip.net.coffee/claude/) 供您实时查看全绿通过效果！

### 2. 独立运行健康体检 (随时检测)

想在命令行下随时检查当前防泄漏保护是否完备，可运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-ClaudeStealth.ps1
```

输出示例：
```text
==========================================================
       🛡️ Claude 隐身防泄漏环境健康体检报告 (CLI)         
==========================================================
[1/7] 正在检测 CLI 与代码子进程代理环境变量...
  ✅ 系统用户环境变量已注入: HTTP_PROXY=http://127.0.0.1:7897
[2/7] 正在发起 IPv4 代理出口与 Claude 连通性测试...
  ✅ 代理出口正常: 136.66.47.237 (国家: US，延迟: 182ms)
[3/7] 正在探测 IPv6 旁路泄漏状态...
  ✅ IPv6 旁路已完全阻断 (无法直连外网 IPv6，杜绝国内真实 IP 绕过代理)
[4/7] 正在检测 WebRTC STUN UDP 防火墙隔离状态...
  ✅ Windows 防火墙已激活 STUN UDP 阻断规则 (端口 3478, 19302~19309 已锁定)
  ✅ Windows 防火墙已激活 Chrome UDP 直连隔离规则
[5/7] 正在检测 Windows 智能多宿主 DNS 防泄露策略...
  ✅ 智能多宿主名称解析 (SMHNR) 已禁用 (杜绝向国内网卡并发探测 DNS)
[6/7] 正在检测系统时区与地理归属...
  ✅ 系统时区与区域已匹配美国: Pacific Standard Time (GeoID: 244)
[7/7] 正在检测浏览器 WebRTC 与语言企业策略...
  ✅ Chrome 组策略生效: disable_non_proxied_udp 且锁定 en-US 语言
==========================================================
  🎉 体检通过！各项指标评级: [A+ 极致隐身安全] (7/7)
  🛡️ WebRTC、IPv6、DNS、时区与语言已 100% 物理级隔离！
==========================================================
```

### 3. 恢复日常工作模式

当您用完 Claude，需要恢复常规中国时区（UTC+8）、恢复 IPv6 访问与中文日常办公环境时，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-ClaudeStealth.ps1
```

所有防火墙规则、组策略、IPv6 协议栈、代理环境变量与系统时区均会根据快照精准无损还原。

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
