<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { EventsOn } from '../wailsjs/runtime/runtime'
import { 
  GetStatus, 
  GetTrafficNow, 
  ToggleStealth, 
  SetUpstreamPort, 
  ClearTrafficLogs, 
  TestNodeLatency, 
  RunFullCheck,
  WipeClaudeDeviceFingerprint,
  DismissRiskAlert,
  ToggleAutoStart,
  GetAutoStart
} from '../wailsjs/go/main/App'

// 状态核心
const isProtected = ref(false)
const isLoading = ref(false)
const statusMessage = ref('安全网关正在监听 127.0.0.1:8999 (Fail-Closed 物理熔断)')
const upstreamPort = ref('7897')
const isAutoStart = ref(false)
const blockedCount = ref(0)

// 流量监控数据
const speedIn = ref(0)
const speedOut = ref(0)
const totalIn = ref(0)
const totalOut = ref(0)
const claudeIn = ref(0)
const claudeOut = ref(0)
const activeConns = ref(0)
const connectionLogs = ref([])
const riskAlert = ref(null)

// 节点出口探测
const nodeInfo = ref({
  ip: '--',
  loc: '--',
  latency: 0,
  isUS: false,
  isTesting: false
})

// 日志分类筛选
const filterMode = ref('all') // 'all', 'claude', 'active', 'blocked'
const filteredLogs = computed(() => {
  if (filterMode.value === 'claude') {
    return connectionLogs.value.filter(l => l.isClaude)
  }
  if (filterMode.value === 'active') {
    return connectionLogs.value.filter(l => l.status === 'Active')
  }
  if (filterMode.value === 'blocked') {
    return connectionLogs.value.filter(l => l.status && l.status.includes('Blocked'))
  }
  return connectionLogs.value
})

const claudeLogCount = computed(() => connectionLogs.value.filter(l => l.isClaude).length)
const activeLogCount = computed(() => connectionLogs.value.filter(l => l.status === 'Active').length)
const blockedLogCount = computed(() => connectionLogs.value.filter(l => l.status && l.status.includes('Blocked')).length)

// 计算 Claude 流量与总流量占比
const claudeTotalBytes = computed(() => claudeIn.value + claudeOut.value)
const claudeSharePercent = computed(() => {
  const allTotal = totalIn.value + totalOut.value
  if (allTotal <= 0) return 0
  const pct = Math.round((claudeTotalBytes.value / allTotal) * 100)
  return Math.min(100, Math.max(0, pct))
})

// 10项体检弹窗
const showCheckModal = ref(false)
const isCheckingHealth = ref(false)
const healthReport = ref({
  score: 10,
  total: 10,
  grade: 'A+ 极致隐身安全 (满分)',
  items: []
})

// 折线图历史队列 (30 秒)
const historyIn = ref(new Array(30).fill(0))
const historyOut = ref(new Array(30).fill(0))

function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return (bytes / Math.pow(k, i)).toFixed(1) + ' ' + sizes[i]
}

function formatSpeed(bytesPerSec) {
  return formatBytes(bytesPerSec) + '/s'
}

// 切换防护
async function handleToggle() {
  isLoading.value = true
  const targetState = !isProtected.value
  statusMessage.value = targetState ? '正在应用系统级加固与防火墙规则...' : '正在恢复系统默认网络设置...'

  try {
    const res = await ToggleStealth(targetState)
    statusMessage.value = res || (targetState ? '防护已生效' : '已恢复默认')
    isProtected.value = targetState
  } catch (err) {
    statusMessage.value = '操作遇到异常: ' + (err?.message || err)
  } finally {
    isLoading.value = false
  }
}

// 探测节点延迟与出口
async function checkNodeLatency() {
  if (nodeInfo.value.isTesting) return
  nodeInfo.value.isTesting = true
  try {
    const res = await TestNodeLatency()
    if (res && res.success) {
      nodeInfo.value.ip = res.ip || '已连接'
      nodeInfo.value.loc = res.loc || 'US'
      nodeInfo.value.latency = res.latency || 0
      nodeInfo.value.isUS = res.isUS
      statusMessage.value = `节点连通正常: ${res.ip} (${res.loc}) · 延迟 ${res.latency}ms`
    } else {
      statusMessage.value = '节点探测失败: ' + (res?.error || '连接超时')
    }
  } catch (err) {
    statusMessage.value = '探测异常: ' + (err?.message || err)
  } finally {
    nodeInfo.value.isTesting = false
  }
}

// 更改上游代理端口
async function promptChangePort() {
  const current = upstreamPort.value || '7897'
  const newPort = window.prompt('请输入本地代理软件的 HTTP/SOCKS 端口 (例如 Clash Verge 为 7897，Clash 为 7890，v2rayN 为 10809):', current)
  if (newPort && newPort.trim() && newPort !== current) {
    const res = await SetUpstreamPort(newPort.trim())
    upstreamPort.value = newPort.trim()
    statusMessage.value = res
  }
}

// 清空日志
async function handleClearLogs() {
  await ClearTrafficLogs()
  connectionLogs.value = []
  statusMessage.value = '已清空本地连接审计日志'
}

// 一键抹除硬件指纹
async function wipeFingerprint() {
  const confirmed = window.confirm('确定要深度抹除 Claude 本地设备指纹 (ant-did)、沙箱缓存与残留吗？\n\n这将关闭正在运行的 Claude 桌面端，彻底粉碎硬件识别标记，让电脑恢复为从未登录过 Claude 的崭新设备。')
  if (!confirmed) return
  try {
    const res = await WipeClaudeDeviceFingerprint()
    alert(res.message || '重置完成！')
    statusMessage.value = '已彻底清除旧硬件指纹 ant-did 与沙箱缓存'
  } catch (err) {
    alert('重置异常: ' + (err?.message || err))
  }
}

// 忽略风控告警
async function dismissRisk() {
  await DismissRiskAlert()
  riskAlert.value = null
}

// 切换开机自启
async function toggleAutoStart() {
  const target = !isAutoStart.value
  isAutoStart.value = await ToggleAutoStart(target)
  statusMessage.value = isAutoStart.value ? '已开启 Windows 开机自启动' : '已关闭开机自启'
}

// 运行完整 10 项健康体检
async function runHealthCheck() {
  showCheckModal.value = true
  isCheckingHealth.value = true
  try {
    const rep = await RunFullCheck()
    if (rep && rep.items) {
      healthReport.value = rep
    }
  } catch (err) {
    console.error(err)
  } finally {
    isCheckingHealth.value = false
  }
}

// 状态同步
async function refreshStatus() {
  try {
    const res = await GetStatus()
    if (res) {
      isProtected.value = res.isProtected
      if (res.upstreamPort) upstreamPort.value = res.upstreamPort
      if (res.isAutoStart !== undefined) isAutoStart.value = res.isAutoStart
    }
    isAutoStart.value = await GetAutoStart()
  } catch {}
}

function handleTrafficUpdate(data) {
  if (!data) return
  speedIn.value = data.speedIn || 0
  speedOut.value = data.speedOut || 0
  totalIn.value = data.totalIn || 0
  totalOut.value = data.totalOut || 0
  claudeIn.value = data.claudeIn || 0
  claudeOut.value = data.claudeOut || 0
  activeConns.value = data.activeConns || 0
  if (data.blockedCount !== undefined) blockedCount.value = data.blockedCount
  if (data.upstreamPort) upstreamPort.value = data.upstreamPort
  if (data.riskAlert) riskAlert.value = data.riskAlert

  if (data.logs && Array.isArray(data.logs)) {
    connectionLogs.value = data.logs.slice().reverse()
  }

  historyIn.value.push(data.speedIn || 0)
  historyIn.value.shift()

  historyOut.value.push(data.speedOut || 0)
  historyOut.value.shift()
}

// 计算 SVG 折线路径与渐变填充闭合路径
const svgPathIn = computed(() => makeSvgPath(historyIn.value))
const svgPathOut = computed(() => makeSvgPath(historyOut.value))
const svgAreaIn = computed(() => makeSvgArea(historyIn.value))
const svgAreaOut = computed(() => makeSvgArea(historyOut.value))

function makeSvgPath(dataArr) {
  const max = Math.max(...dataArr, 1024)
  const width = 600
  const height = 90
  const step = width / (dataArr.length - 1)

  const points = dataArr.map((val, idx) => {
    const x = idx * step
    const y = height - (val / max) * (height - 12) - 6
    return `${x.toFixed(1)},${y.toFixed(1)}`
  })

  return 'M ' + points.join(' L ')
}

function makeSvgArea(dataArr) {
  const path = makeSvgPath(dataArr)
  return `${path} L 600,90 L 0,90 Z`
}

onMounted(() => {
  refreshStatus()
  checkNodeLatency()

  try {
    EventsOn('traffic-tick', (data) => {
      handleTrafficUpdate(data)
    })
  } catch (e) {}

  const syncTimer = setInterval(async () => {
    try {
      const stats = await GetTrafficNow()
      if (stats) {
        handleTrafficUpdate(stats)
      }
    } catch (e) {}
  }, 1000)

  onUnmounted(() => {
    clearInterval(syncTimer)
  })
})
</script>

<template>
  <div class="app-container">
    <!-- 顶部 Cyber 导航栏 -->
    <header class="app-header">
      <div class="logo-area">
        <div class="shield-badge" :class="isProtected ? 'shield-pulse-on' : 'shield-pulse-off'">
          <span class="shield-icon">🛡️</span>
        </div>
        <div>
          <div class="title-row">
            <h1 class="title">Claude Stealth Guardian</h1>
            <span class="version-tag">v2.1 Pro</span>
          </div>
          <p class="subtitle">零物理泄露 · 智能流控网关 · 工业级防封架构</p>
        </div>
      </div>

      <!-- 节点出口与测速条目 -->
      <div class="node-status-bar" @click="checkNodeLatency" title="点击立即重新测速">
        <span class="status-dot" :class="nodeInfo.isUS ? 'dot-green' : 'dot-yellow'"></span>
        <span class="node-country">{{ nodeInfo.isUS ? '🇺🇸' : '🌐' }} {{ nodeInfo.loc }}</span>
        <span class="node-ip">{{ nodeInfo.ip }}</span>
        <span class="node-latency">({{ nodeInfo.latency }}ms)</span>
        <button class="mini-btn" :disabled="nodeInfo.isTesting">⚡ 测速</button>
      </div>

      <div class="header-right">
        <button class="action-top-btn" @click="wipeFingerprint" title="彻底清除旧硬件指纹 ant-did 与沙箱残留">
          🧹 重置指纹
        </button>
        <button class="health-check-btn" @click="runHealthCheck">
          🩺 10项体检
        </button>
        
        <!-- Cyber 主控开关 -->
        <button 
          class="master-toggle-btn"
          :class="isProtected ? 'toggle-on' : 'toggle-off'"
          :disabled="isLoading"
          @click="handleToggle"
        >
          <span class="toggle-glow"></span>
          <span v-if="isLoading" class="spinner"></span>
          <span v-else class="toggle-content">
            <span class="toggle-indicator"></span>
            <span>{{ isProtected ? '隐身守护中' : '未开启防护' }}</span>
          </span>
        </button>
      </div>
    </header>

    <!-- Cloudflare 拦截风控告警条 -->
    <div v-if="riskAlert" class="risk-alert-banner">
      <div class="risk-alert-left">
        <span class="risk-icon">⚠️</span>
        <div class="risk-msg">
          <strong>【风控预警】检测到节点异常拦截</strong>：目标 <code>{{ riskAlert.host }}</code> 响应状态码 <code>{{ riskAlert.status }}</code>（{{ riskAlert.reason }}）。建议立即在代理软件中切换干净节点，谨防关联封号！
        </div>
      </div>
      <button class="dismiss-risk-btn" @click="dismissRisk">✕ 知道了</button>
    </div>

    <!-- 主仪表盘内容 -->
    <main class="dashboard-content">
      <!-- 双核控制区：左侧 10 重防御矩阵 + 右侧 4 格流速看板 -->
      <section class="hero-control-grid">
        <!-- 左侧：10 重硬核防御矩阵看板 -->
        <div class="defense-matrix-card">
          <div class="matrix-header">
            <div class="matrix-title-area">
              <span class="matrix-icon">⚡</span>
              <span class="matrix-title">10重硬核系统防御矩阵 (Defense Matrix)</span>
            </div>
            <span class="matrix-badge" :class="isProtected ? 'badge-perfect' : 'badge-idle'">
              {{ isProtected ? '10/10 全绿激活 · 零泄露' : '防护未激活' }}
            </span>
          </div>

          <!-- 10 项防御徽章网格 (点击即刻调出详情) -->
          <div class="matrix-grid">
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">IPv6 旁路全局阻断</span>
            </div>
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">WebRTC STUN 物理隔离</span>
            </div>
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">Windows SMHNR DNS 封锁</span>
            </div>
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">QUIC (UDP 443) 禁用</span>
            </div>
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">Remote DNS 强制代解</span>
            </div>
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">HTML5 物理定位屏蔽</span>
            </div>
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">Claude Desktop 物理熔断</span>
            </div>
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">美区时区与 GeoID 锁定</span>
            </div>
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">en-US 语言头深度伪装</span>
            </div>
            <div class="matrix-item" :class="isProtected ? 'item-on' : 'item-off'" @click="runHealthCheck">
              <span class="item-dot"></span>
              <span class="item-name">Fail-Closed 绝不直连</span>
            </div>
          </div>
        </div>

        <!-- 右侧：流量吞吐与 Claude 专线分析 -->
        <div class="metrics-quad-grid">
          <!-- 流入卡片 -->
          <div class="metric-card card-inflow">
            <div class="card-header">
              <span class="metric-label">🟢 数据流入 (Download)</span>
              <span class="metric-tag">实时带宽</span>
            </div>
            <div class="metric-main">
              <div class="metric-value text-emerald">
                ↓ {{ formatSpeed(speedIn) }}
              </div>
              <div class="metric-total">
                累计流入: <strong>{{ formatBytes(totalIn) }}</strong>
              </div>
            </div>
          </div>

          <!-- 流出卡片 -->
          <div class="metric-card card-outflow">
            <div class="card-header">
              <span class="metric-label">🔴 数据流出 (Upload)</span>
              <span class="metric-tag">实时带宽</span>
            </div>
            <div class="metric-main">
              <div class="metric-value text-rose">
                ↑ {{ formatSpeed(speedOut) }}
              </div>
              <div class="metric-total">
                累计流出: <strong>{{ formatBytes(totalOut) }}</strong>
              </div>
            </div>
          </div>

          <!-- Claude 专线独立占比仪表 -->
          <div class="metric-card card-claude">
            <div class="card-header">
              <span class="metric-label">🟣 Claude 专线消耗</span>
              <span class="metric-tag tag-purple">占比 {{ claudeSharePercent }}%</span>
            </div>
            <div class="metric-main">
              <div class="metric-value text-purple">
                {{ formatBytes(claudeTotalBytes) }}
              </div>
              <div class="metric-total">
                接收: <strong>{{ formatBytes(claudeIn) }}</strong> · 发送: <strong>{{ formatBytes(claudeOut) }}</strong>
              </div>
              <div class="claude-bar-track">
                <div class="claude-bar-fill" :style="{ width: claudeSharePercent + '%' }"></div>
              </div>
            </div>
          </div>

          <!-- 本地中继网关 -->
          <div class="metric-card card-gateway">
            <div class="card-header">
              <span class="metric-label">🌐 本地安全网关</span>
              <span class="metric-tag">127.0.0.1:8999</span>
            </div>
            <div class="metric-main">
              <div class="gateway-info-row">
                <span>活动连接:</span>
                <strong class="text-sky">{{ activeConns }} 个活跃会话</strong>
              </div>
              <div class="gateway-info-row">
                <span>上游中继:</span>
                <span class="upstream-tag" @click="promptChangePort" title="点击更改端口">
                  127.0.0.1:<strong>{{ upstreamPort }}</strong> ⚙️
                </span>
              </div>
              <div class="gateway-info-row">
                <span>防护机制:</span>
                <span class="text-emerald font-mono">严格 Fail-Closed</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- 实时流速趋势波形折线图 (带高光区域填充) -->
      <section class="chart-panel">
        <div class="panel-header">
          <div class="chart-title-group">
            <span class="panel-title">📈 实时进出流量心跳波形 (近 30 秒)</span>
            <span class="pulse-tag">● 实时采样</span>
          </div>
          <div class="chart-legend">
            <span class="legend-item text-emerald">● 流入 (Inflow)</span>
            <span class="legend-item text-rose">● 流出 (Outflow)</span>
          </div>
        </div>
        <div class="chart-wrapper">
          <svg viewBox="0 0 600 90" preserveAspectRatio="none" class="traffic-svg">
            <defs>
              <linearGradient id="gradIn" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="#10b981" stop-opacity="0.35" />
                <stop offset="100%" stop-color="#10b981" stop-opacity="0.0" />
              </linearGradient>
              <linearGradient id="gradOut" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="#f43f5e" stop-opacity="0.3" />
                <stop offset="100%" stop-color="#f43f5e" stop-opacity="0.0" />
              </linearGradient>
            </defs>

            <!-- 网格参考线 -->
            <line x1="0" y1="20" x2="600" y2="20" stroke="#17223b" stroke-dasharray="3,3" />
            <line x1="0" y1="50" x2="600" y2="50" stroke="#17223b" stroke-dasharray="3,3" />
            <line x1="0" y1="80" x2="600" y2="80" stroke="#17223b" stroke-dasharray="3,3" />
            
            <!-- 渐变区域填充 -->
            <path :d="svgAreaIn" fill="url(#gradIn)" />
            <path :d="svgAreaOut" fill="url(#gradOut)" />

            <!-- 发光折线路径 -->
            <path :d="svgPathIn" fill="none" stroke="#10b981" stroke-width="2.5" />
            <path :d="svgPathOut" fill="none" stroke="#f43f5e" stroke-width="2.5" />
          </svg>
        </div>
      </section>

      <!-- 活跃连接审计流水表 (带过滤与 Claude 专线高亮) -->
      <section class="connections-table-card">
        <div class="panel-header">
          <div class="filter-group">
            <span class="panel-title">📋 实时网络连接审计与防御流水</span>
            <div class="filter-tabs">
              <button 
                class="tab-btn" 
                :class="{ active: filterMode === 'all' }" 
                @click="filterMode = 'all'"
              >
                全部连接 ({{ connectionLogs.length }})
              </button>
              <button 
                class="tab-btn tab-claude" 
                :class="{ active: filterMode === 'claude' }" 
                @click="filterMode = 'claude'"
              >
                🟣 仅看 Claude 专线 ({{ claudeLogCount }})
              </button>
              <button 
                class="tab-btn" 
                :class="{ active: filterMode === 'active' }" 
                @click="filterMode = 'active'"
              >
                ⚡ 活跃连接 ({{ activeLogCount }})
              </button>
              <button 
                class="tab-btn tab-blocked" 
                :class="{ active: filterMode === 'blocked' }" 
                @click="filterMode = 'blocked'"
              >
                🛡️ 拦截记录 ({{ blockedLogCount }})
              </button>
            </div>
          </div>

          <div class="action-buttons">
            <button class="clear-btn" @click="handleClearLogs" title="清空日志流水">
              🗑️ 清空流水
            </button>
          </div>
        </div>

        <div class="table-container">
          <table class="audit-table">
            <thead>
              <tr>
                <th>连接时间</th>
                <th>目标域名 / 端口</th>
                <th>协议方法</th>
                <th>数据流出 (Upload)</th>
                <th>数据流入 (Download)</th>
                <th>连接状态</th>
              </tr>
            </thead>
            <tbody>
              <tr 
                v-for="log in filteredLogs" 
                :key="log.id"
                :class="{ 'row-claude': log.isClaude }"
              >
                <td class="col-time">{{ log.time }}</td>
                <td class="col-host">
                  <span v-if="log.isClaude" class="claude-badge">🟣 Claude 专线</span>
                  {{ log.host }}
                </td>
                <td><span class="method-tag">{{ log.method }}</span></td>
                <td class="text-rose font-mono">↑ {{ formatBytes(log.bytesOut) }}</td>
                <td class="text-emerald font-mono">↓ {{ formatBytes(log.bytesIn) }}</td>
                <td>
                  <span class="status-tag" :class="log.status === 'Active' ? 'tag-active' : (log.status && log.status.includes('Blocked') ? 'tag-blocked' : 'tag-closed')">
                    {{ log.status === 'Active' ? '● 活跃会话' : (log.status && log.status.includes('Blocked') ? '🛡️已物理熔断' : '✓ 已完成') }}
                  </span>
                </td>
              </tr>
              <tr v-if="filteredLogs.length === 0">
                <td colspan="6" class="empty-state">
                  {{ filterMode === 'claude' ? '暂未捕获到 Claude 相关流量请求（访问 claude.ai 时将自动罗列）' : '网关运行中，尚未捕获到连接请求' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </main>

    <!-- 底部 Cyber 状态条 -->
    <footer class="app-footer">
      <div class="footer-left">
        <span class="status-dot-inline" :class="isProtected ? 'dot-green' : 'dot-yellow'"></span>
        <span>{{ statusMessage }}</span>
      </div>
      <div class="footer-right">
        <span class="defense-counter">🛡️ 累计物理阻断风险: <strong>{{ blockedCount }}</strong> 次</span>
        <span class="divider">|</span>
        <button class="autostart-btn" @click="toggleAutoStart">
          🚀 开机自启: {{ isAutoStart ? '已开启' : '未开启' }}
        </button>
        <span class="divider">|</span>
        <span class="brand-text">Claude Stealth Mode · 零物理泄露工业级架构</span>
      </div>
    </footer>

    <!-- 10 项防护指标健康体检弹窗 (Modal) -->
    <div v-if="showCheckModal" class="modal-backdrop" @click.self="showCheckModal = false">
      <div class="modal-content">
        <div class="modal-header">
          <div class="modal-title-area">
            <h3>🛡️ 系统防泄漏健康体检报告</h3>
            <span class="modal-grade" :class="healthReport.score >= 10 ? 'grade-perfect' : 'grade-good'">
              评级: {{ healthReport.grade }} ({{ healthReport.score }}/{{ healthReport.total }})
            </span>
          </div>
          <button class="close-btn" @click="showCheckModal = false">✕</button>
        </div>

        <div class="modal-body">
          <div v-if="isCheckingHealth" class="modal-loading">
            <span class="spinner"></span> 正在对 10 项底层网络、防火墙与注册表策略进行深度诊断...
          </div>
          <div v-else class="check-items-list">
            <div 
              v-for="(item, idx) in healthReport.items" 
              :key="idx" 
              class="check-item-row"
              :class="item.passed ? 'check-pass' : 'check-fail'"
            >
              <div class="check-icon">
                {{ item.passed ? '✅' : '⚠️' }}
              </div>
              <div class="check-info">
                <div class="check-title">{{ idx + 1 }}. {{ item.title }}</div>
                <div class="check-desc">{{ item.desc }}</div>
              </div>
              <div class="check-status-tag">
                {{ item.passed ? '安全达标' : '需要加固' }}
              </div>
            </div>
          </div>
        </div>

        <div class="modal-footer">
          <button class="modal-action-btn" :disabled="isCheckingHealth" @click="runHealthCheck">
            🔄 重新检测
          </button>
          <button class="modal-close-btn" @click="showCheckModal = false">
            关闭
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.app-container {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background-color: #070a12;
  background-image: radial-gradient(circle at 10% 20%, rgba(14, 165, 233, 0.05) 0%, transparent 40%),
                    radial-gradient(circle at 90% 80%, rgba(168, 85, 247, 0.04) 0%, transparent 40%);
  color: #f1f5f9;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
  user-select: none;
  overflow: hidden;
  position: relative;
}

/* 顶部导航 */
.app-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 20px;
  background-color: #0c1220;
  border-bottom: 1px solid #1a253c;
  gap: 12px;
}

.logo-area {
  display: flex;
  align-items: center;
  gap: 12px;
}

.shield-badge {
  width: 36px;
  height: 36px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  background-color: #131c31;
  border: 1px solid #243456;
  transition: all 0.3s ease;
}

.shield-pulse-on {
  border-color: #10b981;
  box-shadow: 0 0 12px rgba(16, 185, 129, 0.35);
}

.shield-pulse-off {
  border-color: #475569;
}

.title-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.title {
  margin: 0;
  font-size: 16px;
  font-weight: 700;
  letter-spacing: -0.02em;
  color: #ffffff;
}

.version-tag {
  background: linear-gradient(135deg, #0284c7, #38bdf8);
  color: white;
  font-size: 9px;
  padding: 1px 6px;
  border-radius: 10px;
  font-weight: 700;
  letter-spacing: 0.05em;
}

.subtitle {
  margin: 1px 0 0 0;
  font-size: 10px;
  color: #64748b;
}

/* 节点探测条 */
.node-status-bar {
  display: flex;
  align-items: center;
  gap: 8px;
  background-color: rgba(19, 28, 49, 0.8);
  border: 1px solid #243456;
  padding: 4px 12px;
  border-radius: 20px;
  cursor: pointer;
  transition: all 0.2s ease;
}

.node-status-bar:hover {
  background-color: rgba(30, 41, 59, 0.9);
  border-color: #38bdf8;
}

.status-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
}

.status-dot-inline {
  display: inline-block;
  width: 6px;
  height: 6px;
  border-radius: 50%;
  margin-right: 6px;
}

.dot-green {
  background-color: #10b981;
  box-shadow: 0 0 6px #10b981;
}

.dot-yellow {
  background-color: #eab308;
  box-shadow: 0 0 6px #eab308;
}

.node-country {
  font-size: 11px;
  font-weight: 600;
  color: #f8fafc;
}

.node-ip {
  font-size: 11px;
  color: #94a3b8;
  font-family: monospace;
}

.node-latency {
  font-size: 10px;
  color: #38bdf8;
  font-family: monospace;
}

.mini-btn {
  background: transparent;
  border: none;
  color: #38bdf8;
  font-size: 10px;
  cursor: pointer;
  padding: 0 2px;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 10px;
}

.action-top-btn {
  background-color: rgba(19, 28, 49, 0.8);
  border: 1px solid #243456;
  color: #c084fc;
  padding: 5px 11px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.action-top-btn:hover {
  background-color: #7c3aed;
  color: white;
  border-color: #7c3aed;
  box-shadow: 0 0 10px rgba(124, 58, 237, 0.4);
}

.health-check-btn {
  background-color: rgba(19, 28, 49, 0.8);
  border: 1px solid #243456;
  color: #38bdf8;
  padding: 5px 12px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.health-check-btn:hover {
  background-color: #0284c7;
  color: white;
  border-color: #0284c7;
  box-shadow: 0 0 10px rgba(2, 132, 199, 0.4);
}

/* Cyber 主控开关 */
.master-toggle-btn {
  position: relative;
  border: none;
  padding: 6px 18px;
  border-radius: 24px;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s ease;
  overflow: hidden;
}

.toggle-on {
  background: linear-gradient(135deg, #059669, #10b981);
  color: white;
  box-shadow: 0 0 14px rgba(16, 185, 129, 0.45);
}

.toggle-off {
  background-color: #1e293b;
  color: #94a3b8;
  border: 1px solid #334155;
}

.toggle-content {
  display: flex;
  align-items: center;
  gap: 6px;
}

.toggle-indicator {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background-color: currentColor;
}

.master-toggle-btn:hover {
  transform: translateY(-1px);
}

.master-toggle-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

/* 风控警报横幅 */
.risk-alert-banner {
  background: linear-gradient(90deg, #7f1d1d, #991b1b);
  border-bottom: 1px solid #ef4444;
  color: #fee2e2;
  padding: 6px 18px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 11px;
  animation: slideDown 0.3s ease;
}

.risk-alert-left {
  display: flex;
  align-items: center;
  gap: 8px;
}

.risk-icon {
  font-size: 14px;
}

.risk-msg code {
  background: rgba(0, 0, 0, 0.3);
  padding: 1px 4px;
  border-radius: 3px;
  color: #fef08a;
}

.dismiss-risk-btn {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.3);
  color: white;
  border-radius: 4px;
  padding: 2px 8px;
  font-size: 10px;
  cursor: pointer;
}

.dismiss-risk-btn:hover {
  background: rgba(255, 255, 255, 0.2);
}

/* 主内容区 */
.dashboard-content {
  flex: 1;
  padding: 12px 20px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  overflow-y: auto;
}

/* 双核布局：左侧 10 重矩阵 + 右侧 4 格流速 */
.hero-control-grid {
  display: grid;
  grid-template-columns: 1.15fr 1.85fr;
  gap: 12px;
}

/* 10 重防御矩阵卡片 */
.defense-matrix-card {
  background: linear-gradient(145deg, #0e1526, #111a2f);
  border: 1px solid #1e2c4a;
  border-radius: 10px;
  padding: 12px 14px;
  display: flex;
  flex-direction: column;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.35);
}

.matrix-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
  padding-bottom: 6px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
}

.matrix-title-area {
  display: flex;
  align-items: center;
  gap: 6px;
}

.matrix-icon {
  font-size: 13px;
  color: #38bdf8;
}

.matrix-title {
  font-size: 12px;
  font-weight: 700;
  color: #e2e8f0;
}

.matrix-badge {
  font-size: 10px;
  padding: 2px 6px;
  border-radius: 4px;
  font-weight: 600;
}

.badge-perfect {
  background-color: rgba(16, 185, 129, 0.15);
  color: #10b981;
  border: 1px solid rgba(16, 185, 129, 0.3);
}

.badge-idle {
  background-color: rgba(148, 163, 184, 0.1);
  color: #94a3b8;
  border: 1px solid rgba(148, 163, 184, 0.2);
}

.matrix-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 5px;
}

.matrix-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-radius: 5px;
  font-size: 10px;
  cursor: pointer;
  transition: all 0.2s ease;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.matrix-item:hover {
  transform: translateY(-1px);
}

.item-on {
  background-color: rgba(16, 185, 129, 0.08);
  border: 1px solid rgba(16, 185, 129, 0.2);
  color: #34d399;
}

.item-off {
  background-color: rgba(71, 85, 105, 0.15);
  border: 1px solid rgba(71, 85, 105, 0.2);
  color: #64748b;
}

.item-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background-color: currentColor;
  flex-shrink: 0;
}

/* 4格流量卡片 */
.metrics-quad-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.metric-card {
  background: linear-gradient(145deg, #0e1526, #111a2f);
  border: 1px solid #1e2c4a;
  border-radius: 8px;
  padding: 9px 12px;
  position: relative;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

.card-inflow {
  border-left: 3px solid #10b981;
}

.card-outflow {
  border-left: 3px solid #f43f5e;
}

.card-claude {
  border-left: 3px solid #a855f7;
}

.card-gateway {
  border-left: 3px solid #38bdf8;
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.metric-label {
  font-size: 11px;
  font-weight: 600;
  color: #94a3b8;
}

.metric-tag {
  font-size: 9px;
  padding: 1px 5px;
  border-radius: 3px;
  background-color: #17223b;
  color: #64748b;
}

.tag-purple {
  background-color: rgba(168, 85, 247, 0.15);
  color: #c084fc;
}

.metric-value {
  font-size: 19px;
  font-weight: 700;
  font-family: monospace;
  margin: 2px 0;
}

.text-emerald {
  color: #10b981;
}

.text-rose {
  color: #f43f5e;
}

.text-purple {
  color: #c084fc;
}

.text-sky {
  color: #38bdf8;
}

.metric-total {
  font-size: 10px;
  color: #64748b;
}

.metric-total strong {
  color: #cbd5e1;
}

.claude-bar-track {
  width: 100%;
  height: 3px;
  background-color: #1a253c;
  border-radius: 2px;
  margin-top: 4px;
  overflow: hidden;
}

.claude-bar-fill {
  height: 100%;
  background: linear-gradient(90deg, #9333ea, #a855f7);
  transition: width 0.3s ease;
}

.gateway-info-row {
  display: flex;
  justify-content: space-between;
  font-size: 10px;
  color: #94a3b8;
  margin-top: 2px;
}

.upstream-tag {
  background-color: #17223b;
  padding: 1px 5px;
  border-radius: 3px;
  cursor: pointer;
  color: #38bdf8;
  transition: all 0.2s;
}

.upstream-tag:hover {
  background-color: #243456;
  color: #ffffff;
}

/* 折线图 */
.chart-panel {
  background: linear-gradient(145deg, #0e1526, #111a2f);
  border: 1px solid #1e2c4a;
  border-radius: 8px;
  padding: 8px 14px;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 4px;
}

.chart-title-group {
  display: flex;
  align-items: center;
  gap: 8px;
}

.panel-title {
  font-size: 11px;
  font-weight: 600;
  color: #e2e8f0;
}

.pulse-tag {
  font-size: 9px;
  color: #34d399;
  font-family: monospace;
}

.chart-legend {
  display: flex;
  gap: 12px;
  font-size: 10px;
}

.chart-wrapper {
  height: 50px;
  width: 100%;
}

.traffic-svg {
  width: 100%;
  height: 100%;
}

/* 审计列表 */
.connections-table-card {
  flex: 1;
  background: linear-gradient(145deg, #0e1526, #111a2f);
  border: 1px solid #1e2c4a;
  border-radius: 8px;
  padding: 8px 14px;
  display: flex;
  flex-direction: column;
  min-height: 150px;
}

.filter-group {
  display: flex;
  align-items: center;
  gap: 10px;
}

.filter-tabs {
  display: flex;
  gap: 4px;
}

.tab-btn {
  background-color: #131c31;
  border: 1px solid #243456;
  color: #94a3b8;
  padding: 3px 8px;
  border-radius: 4px;
  font-size: 10px;
  cursor: pointer;
  transition: all 0.2s;
}

.tab-btn:hover {
  background-color: #243456;
  color: #ffffff;
}

.tab-btn.active {
  background-color: #0284c7;
  border-color: #0284c7;
  color: #ffffff;
}

.tab-btn.tab-claude.active {
  background-color: #7c3aed;
  border-color: #7c3aed;
}

.tab-btn.tab-blocked.active {
  background-color: #e11d48;
  border-color: #e11d48;
}

.clear-btn {
  background-color: transparent;
  border: 1px solid #243456;
  color: #94a3b8;
  padding: 3px 8px;
  border-radius: 4px;
  font-size: 10px;
  cursor: pointer;
  transition: all 0.2s;
}

.clear-btn:hover {
  background-color: #ef4444;
  border-color: #ef4444;
  color: #ffffff;
}

.table-container {
  flex: 1;
  overflow-y: auto;
  margin-top: 4px;
}

.audit-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 11px;
}

.audit-table th {
  text-align: left;
  padding: 5px 8px;
  color: #64748b;
  border-bottom: 1px solid #1a253c;
  font-weight: 500;
}

.audit-table td {
  padding: 4px 8px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.03);
  color: #cbd5e1;
}

.row-claude {
  background-color: rgba(124, 58, 237, 0.08);
}

.claude-badge {
  background-color: #7c3aed;
  color: white;
  font-size: 9px;
  padding: 1px 4px;
  border-radius: 3px;
  margin-right: 5px;
  font-weight: 600;
}

.col-time {
  color: #64748b;
  font-family: monospace;
}

.col-host {
  font-weight: 500;
  max-width: 250px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.method-tag {
  background-color: #17223b;
  padding: 1px 5px;
  border-radius: 3px;
  font-size: 9px;
  color: #94a3b8;
  font-family: monospace;
}

.status-tag {
  padding: 1px 5px;
  border-radius: 3px;
  font-size: 9px;
  font-weight: 600;
}

.tag-active {
  background-color: rgba(56, 189, 248, 0.15);
  color: #38bdf8;
}

.tag-closed {
  background-color: rgba(148, 163, 184, 0.1);
  color: #64748b;
}

.tag-blocked {
  background-color: rgba(239, 68, 68, 0.15);
  color: #ef4444;
}

.empty-state {
  text-align: center;
  padding: 24px;
  color: #475569;
}

/* 底部状态 */
.app-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 5px 18px;
  background-color: #070a12;
  border-top: 1px solid #1a253c;
  font-size: 11px;
  color: #64748b;
}

.footer-left {
  display: flex;
  align-items: center;
}

.footer-right {
  display: flex;
  align-items: center;
  gap: 10px;
}

.defense-counter strong {
  color: #38bdf8;
}

.autostart-btn {
  background: transparent;
  border: 1px solid #243456;
  color: #94a3b8;
  padding: 2px 7px;
  border-radius: 4px;
  font-size: 10px;
  cursor: pointer;
  transition: all 0.2s;
}

.autostart-btn:hover {
  background-color: #131c31;
  color: #38bdf8;
}

.divider {
  color: #1a253c;
}

.brand-text {
  color: #475569;
}

/* 弹窗 Modal */
.modal-backdrop {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.75);
  backdrop-filter: blur(5px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
}

.modal-content {
  background-color: #0c1220;
  border: 1px solid #243456;
  border-radius: 12px;
  width: 580px;
  max-width: 90vw;
  max-height: 85vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 18px;
  border-bottom: 1px solid #1a253c;
}

.modal-title-area h3 {
  margin: 0;
  font-size: 14px;
  color: #ffffff;
}

.modal-grade {
  display: inline-block;
  margin-top: 3px;
  font-size: 11px;
  padding: 2px 7px;
  border-radius: 4px;
  font-weight: 600;
}

.grade-perfect {
  background-color: rgba(16, 185, 129, 0.15);
  color: #10b981;
}

.grade-good {
  background-color: rgba(234, 179, 8, 0.15);
  color: #eab308;
}

.close-btn {
  background: transparent;
  border: none;
  color: #94a3b8;
  font-size: 16px;
  cursor: pointer;
}

.modal-body {
  padding: 12px 18px;
  overflow-y: auto;
  max-height: 440px;
}

.modal-loading {
  text-align: center;
  padding: 30px;
  color: #38bdf8;
  font-size: 12px;
}

.check-items-list {
  display: flex;
  flex-direction: column;
  gap: 7px;
}

.check-item-row {
  display: flex;
  align-items: center;
  padding: 7px 10px;
  border-radius: 6px;
  background-color: #131c31;
  border: 1px solid #243456;
}

.check-pass {
  border-left: 3px solid #10b981;
}

.check-fail {
  border-left: 3px solid #eab308;
}

.check-icon {
  font-size: 14px;
  margin-right: 10px;
}

.check-info {
  flex: 1;
}

.check-title {
  font-size: 12px;
  font-weight: 600;
  color: #f1f5f9;
}

.check-desc {
  font-size: 10px;
  color: #94a3b8;
  margin-top: 1px;
}

.check-status-tag {
  font-size: 10px;
  padding: 1px 6px;
  border-radius: 3px;
  background-color: rgba(12, 18, 32, 0.6);
  color: #cbd5e1;
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding: 10px 18px;
  border-top: 1px solid #1a253c;
  background-color: #070a12;
  border-bottom-left-radius: 12px;
  border-bottom-right-radius: 12px;
}

.modal-action-btn {
  background-color: #0284c7;
  color: white;
  border: none;
  padding: 5px 12px;
  border-radius: 5px;
  font-size: 11px;
  cursor: pointer;
}

.modal-close-btn {
  background-color: #243456;
  color: white;
  border: none;
  padding: 5px 12px;
  border-radius: 5px;
  font-size: 11px;
  cursor: pointer;
}

.spinner {
  display: inline-block;
  width: 11px;
  height: 11px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-radius: 50%;
  border-top-color: white;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>
