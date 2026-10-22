# Claude Stealth Mode (Claude 免 TUN 终极防封隐身工具)

🚀 **专为 Windows 平台打造的 Claude / Claude Desktop 防区域检测与防封号隐身脚本。**

无需开启虚拟网卡（TUN 模式），彻底解决 Claude 网页端与桌面端（特别是写代码/调用本地终端时）因为真实 IP 泄漏、WebRTC 穿透、时区语言冲突导致的频繁封号与区域拦截（*“App unavailable in your region”*）。

---

## 🌟 核心痛点与解决机制

| 泄漏与封号风险点 | 普通代理（未开 TUN）的表现 | 本工具解决方案 |
| :--- | :--- | :--- |
| **桌面端代码子进程** | Claude 桌面端执行本地命令（PowerShell/Git/Node/Python）时**直接绕过代理裸连国内真实 IP** | 自动向系统注入 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` 及 Git 代理，强制所有命令行程序走代理 |
| **WebRTC 穿透** | 浏览器 WebRTC 绕过 WinINet 代理，通过物理网卡向 STUN 发 UDP，直接暴露国内真实 IP | 注入 Chrome 策略 `disable_non_proxied_udp`，彻底锁死 WebRTC 旁路泄露 |
| **时区与指纹矛盾** | 节点在美国，系统时区却是 `Asia/Shanghai`（差 15~16 小时），前端 JS 秒抓 | 自动切换系统时区为 **美国太平洋时间 (`Pacific Standard Time`)** 并锁定 |
| **语言暴露** | 浏览器默认发送 `Accept-Language: zh-CN` | 自动将 Chrome 首选语言切换为 `en-US,en` |
| **设备硬件指纹关联** | Claude 桌面端在本地写入 `ant-did` 与旧账号终身绑定，换号直接连环封 | 自动扫描并抹除 `ant-did`、`ant-device-registry.json` 及沙箱临时文件，恢复全新设备状态 |

---

## 📁 仓库结构

```text
├── Enable-ClaudeStealth.ps1    # 【一键开启】防检测隐身模式（用 Claude 前运行）
├── Disable-ClaudeStealth.ps1   # 【一键还原】恢复中国标准时间与默认系统设置
├── LICENSE                     # 开源许可证 (MIT)
└── README.md                   # 项目说明文档
```

---

## 🚀 快速使用

### 1. 开启隐身模式

打开 PowerShell（或右键脚本选择“使用 PowerShell 运行”）：

```powershell
powershell -ExecutionPolicy Bypass -File .\Enable-ClaudeStealth.ps1
```

*默认代理端口为 `7897`（Clash Verge 默认混合端口）。如果您使用其他端口，可通过参数指定：*
```powershell
powershell -ExecutionPolicy Bypass -File .\Enable-ClaudeStealth.ps1 -ProxyPort 7890
```

运行后控制台会自动完成：
1. 注入 CLI 代理环境变量与 Git 代理；
2. 切换并锁定系统时区为美国太平洋时间；
3. 配置 Chrome 禁用 WebRTC 泄漏并修改语言为 `en-US`；
4. 清理旧 Claude 客户端硬件指纹残留；
5. 请求 Cloudflare 进行实时出口 IP 与区域自检。

### 2. 恢复日常工作模式

当您用完 Claude，需要恢复中国时区（UTC+8）及日常办公环境时，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-ClaudeStealth.ps1
```

---

## 🔍 配合建议

1. **浏览器环境**：建议在 Chrome 地址栏访问 `chrome://flags/#enable-webrtc-hide-local-ips-with-mdns` 并设为 **Enabled**；
2. **节点选择**：在代理客户端中挑选带有 **“原生”、“家庭宽带”** 标签的节点，避免使用纯机房（Google Cloud、AWS、Azure）IP；
3. **无痕模式**：建议使用 Chrome **无痕窗口（Ctrl + Shift + N）** 访问 Claude，避免历史缓存与被污染的 Cookie 干扰。

---

## ⚖️ 免责声明 (Disclaimer)

本项目仅供网络协议安全测试、WebRTC 防泄漏研究与个人技术交流使用。请遵守当地法律法规以及相关平台的服务条款。
