# Claude Stealth Mode (Claude 免 TUN 终极防封隐身工具)

🚀 **专为 Windows 平台打造的 Claude / Claude Desktop 防区域检测与防封号隐身工具。**

无需开启虚拟网卡（TUN 模式），彻底解决 Claude 网页端与桌面端（特别是写代码/调用本地终端时）因为真实 IP 泄漏、WebRTC 穿透、时区语言冲突导致的频繁封号与区域拦截（*“App unavailable in your region”*）。

---

## 🌟 核心痛点与解决机制

| 泄漏与封号风险点 | 普通代理（未开 TUN）的表现 | 本工具解决方案 |
| :--- | :--- | :--- |
| **桌面端代码子进程** | Claude 桌面端执行本地命令（PowerShell/Git/Node/Python）时**直接绕过代理裸连国内真实 IP** | 自动向系统注入 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`、广播 `WM_SETTINGCHANGE` 并注入 PowerShell Profile，强制所有命令行程序走代理 |
| **WebRTC 穿透 (STUN UDP)** | 浏览器 WebRTC 绕过 WinINet 代理，通过物理网卡向 STUN 发 UDP，直接暴露国内真实公网 IP (`typ srflx`) | 注入 Chrome 策略 `disable_non_proxied_udp`，并配合 [WebRTC Control 扩展](https://chromewebstore.google.com/detail/webrtc-control/fjkmfdakclpmffdikkipmimdogffkvae) 彻底屏蔽 UDP 泄露 |
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
1. 注入 CLI 代理环境变量、Git 代理与 PowerShell 启动 Profile；
2. 切换并锁定系统时区为美国太平洋时间；
3. 配置 Chrome 禁用 WebRTC 泄漏并修改语言为 `en-US`；
4. 清理旧 Claude 客户端硬件指纹残留（`ant-did`）；
5. 请求 Cloudflare 进行实时出口 IP 与区域自检。

### 2. 恢复日常工作模式

当您用完 Claude，需要恢复中国时区（UTC+8）及日常办公环境时，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-ClaudeStealth.ps1
```

---

## 🛡️ 实测通过之黄金配置（实战验证）

针对 Chrome 浏览器在不开 TUN 模式下最难缠的 WebRTC UDP 穿透问题，以下组合已通过实机严格检测：

1. **安装 WebRTC 内存拦截扩展（实测有效）**：
   * 在 Chrome 商店安装 [WebRTC Control](https://chromewebstore.google.com/detail/webrtc-control/fjkmfdakclpmffdikkipmimdogffkvae)；
   * 安装后默认开启，它能在无需重启几百个 Chrome 后台常驻进程的情况下，在内存层彻底阻断 STUN UDP 数据包外发。
2. **实测检验标准（在 [BrowserLeaks WebRTC](https://browserleaks.com/webrtc) 测试）**：
   * **公网 IP 地址 (Public IP)**：显示为 `-`（空白）或与远程代理一致；
   * 红色警告提示 `! WebRTC IP 地址与您的远程 IP 地址不匹配` **彻底消失**；
   * SDP 日志中不再出现包含国内公网 IP 的 `typ srflx` 候选行。
3. **节点纯净度**：
   * 尽量选择非大厂机房（如非 Google Cloud、AWS、Azure）的原生住宅或高质量落地节点，防止因 ASN 属性直接被 Cloudflare 拦截。

---

## ⚖️ 免责声明 (Disclaimer)

本项目仅供网络协议安全测试、WebRTC 防泄漏研究与个人技术交流使用。请遵守当地法律法规以及相关平台的服务条款。
