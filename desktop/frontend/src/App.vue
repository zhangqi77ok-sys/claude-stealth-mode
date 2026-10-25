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
  RunFullCheck 
} from '../wailsjs/go/main/App'

// 状态数据
const isProtected = ref(false)
const isLoading = ref(false)
const statusMessage = ref('安全网关正在监听 127.0.0.1:8999')
const upstreamPort = ref('7897')

// 流量监控数据
const speedIn = ref(0)
const speedOut = ref(0)
const totalIn = ref(0)
const totalOut = ref(0)
const activeConns = ref(0)
const connectionLogs = ref([])

// 节点出口探测
const nodeInfo = ref({
  ip: '--',
  loc: '--',
  latency: 0,
  isUS: false,
  isTesting: false
})

// 日志分类筛选
const filterMode = ref('all') // 'all', 'claude', 'active'
const filteredLogs = computed(() => {
  if (filterMode.value === 'claude') {
    return connectionLogs.value.filter(l => l.isClaude)
  }
  if (filterMode.value === 'active') {
    return connectionLogs.value.filter(l => l.status === 'Active')
  }
  return connectionLogs.value
})

const claudeLogCount = computed(() => connectionLogs.value.filter(l => l.isClaude).length)
const activeLogCount = computed(() => connectionLogs.value.filter(l => l.status === 'Active').length)

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
    }
  } catch {}
}

function handleTrafficUpdate(data) {
  if (!data) return
  speedIn.value = data.speedIn || 0
  speedOut.value = data.speedOut || 0
  totalIn.value = data.totalIn || 0
  totalOut.value = data.totalOut || 0
  activeConns.value = data.activeConns || 0
  if (data.upstreamPort) upstreamPort.value = data.upstreamPort

  if (data.logs && Array.isArray(data.logs)) {
    connectionLogs.value = data.logs.slice().reverse()
  }

  historyIn.value.push(data.speedIn || 0)
  historyIn.value.shift()

  historyOut.value.push(data.speedOut || 0)
  historyOut.value.shift()
}

const svgPathIn = computed(() => makeSvgPath(historyIn.value, '#10b981'))
const svgPathOut = computed(() => makeSvgPath(historyOut.value, '#f43f5e'))

function makeSvgPath(dataArr) {
  const max = Math.max(...dataArr, 1024)
  const width = 600
  const height = 90
  const step = width / (dataArr.length - 1)

  const points = dataArr.map((val, idx) => {
    const x = idx * step
    const y = height - (val / max) * (height - 10) - 5
    return `${x.toFixed(1)},${y.toFixed(1)}`
  })

  return 'M ' + points.join(' L ')
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
    <!-- 顶部导航栏 -->
    <header class="app-header">
      <div class="logo-area">
        <div class="shield-icon">🛡️</div>
        <div>
          <h1 class="title">Claude Stealth Guardian</h1>
          <p class="subtitle">安全网关中继 · 实时数据流入流出监控</p>
        </div>
      </div>

      <!-- 节点出口与测速条目 -->
      <div class="node-status-bar" @click="checkNodeLatency" title="点击立即重新测速">
        <span class="status-dot" :class="nodeInfo.isUS ? 'dot-green' : 'dot-yellow'"></span>
        <span class="node-info-text">
          <span v-if="nodeInfo.isTesting">正在测速...</span>
          <span v-else>
            {{ nodeInfo.loc }}: {{ nodeInfo.ip }} ({{ nodeInfo.latency }}ms)
          </span>
        </span>
        <button class="mini-btn" :disabled="nodeInfo.isTesting">⚡ 测速</button>
      </div>

      <div class="header-right">
        <button class="health-check-btn" @click="runHealthCheck">
          🩺 10项体检
        </button>
        <span class="status-badge" :class="isProtected ? 'badge-safe' : 'badge-idle'">
          {{ isProtected ? '● 防护已激活 (极致隐身)' : '○ 常规日常模式' }}
        </span>
        <button 
          class="toggle-btn"
          :class="isProtected ? 'btn-danger' : 'btn-primary'"
          :disabled="isLoading"
          @click="handleToggle"
        >
          <span v-if="isLoading" class="spinner"></span>
          <span v-else>{{ isProtected ? '停止防护' : '启动防护' }}</span>
        </button>
      </div>
    </header>

    <!-- 主仪表盘内容 -->
    <main class="dashboard-content">
      <!-- 流量监控大卡片 (流入 / 流出 / 网关) -->
      <section class="traffic-metrics-row">
        <!-- 流入卡片 -->
        <div class="metric-card card-inflow">
          <div class="card-header">
            <span class="metric-label">🟢 数据流入 (Inflow / 接收)</span>
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
            <span class="metric-label">🔴 数据流出 (Outflow / 发送)</span>
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

        <!-- 网关状态卡片 -->
        <div class="metric-card card-gateway">
          <div class="card-header">
            <span class="metric-label">🌐 本地中继网关</span>
            <span class="metric-tag">127.0.0.1:8999</span>
          </div>
          <div class="metric-main">
            <div class="gateway-info-row">
              <span>活动连接:</span>
              <strong class="text-sky">{{ activeConns }} 个活跃会话</strong>
            </div>
            <div class="gateway-info-row">
              <span>上游代理:</span>
              <span class="upstream-tag" @click="promptChangePort" title="点击更改端口">
                127.0.0.1:<strong>{{ upstreamPort }}</strong> ⚙️
              </span>
            </div>
            <div class="gateway-info-row">
              <span>协议过滤:</span>
              <span class="text-emerald">Accept-Language 自动脱敏</span>
            </div>
          </div>
        </div>
      </section>

      <!-- 实时流速趋势波形折线图 -->
      <section class="chart-panel">
        <div class="panel-header">
          <span class="panel-title">📈 实时进出流量趋势波形 (近 30 秒)</span>
          <div class="chart-legend">
            <span class="legend-item text-emerald">● 流入 (Inflow)</span>
            <span class="legend-item text-rose">● 流出 (Outflow)</span>
          </div>
        </div>
        <div class="chart-wrapper">
          <svg viewBox="0 0 600 90" preserveAspectRatio="none" class="traffic-svg">
            <line x1="0" y1="20" x2="600" y2="20" stroke="#1e293b" stroke-dasharray="3,3" />
            <line x1="0" y1="50" x2="600" y2="50" stroke="#1e293b" stroke-dasharray="3,3" />
            <line x1="0" y1="80" x2="600" y2="80" stroke="#1e293b" stroke-dasharray="3,3" />
            
            <path :d="svgPathIn" fill="none" stroke="#10b981" stroke-width="2.5" />
            <path :d="svgPathOut" fill="none" stroke="#f43f5e" stroke-width="2.5" />
          </svg>
        </div>
      </section>

      <!-- 10 项防护健康指示标 -->
      <section class="security-badges-bar">
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'" @click="runHealthCheck">
          <span class="dot"></span> IPv6 旁路封堵
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'" @click="runHealthCheck">
          <span class="dot"></span> WebRTC STUN 隔离
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'" @click="runHealthCheck">
          <span class="dot"></span> Windows 多宿主 DNS 封堵
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'" @click="runHealthCheck">
          <span class="dot"></span> QUIC (UDP 443) 禁用
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'" @click="runHealthCheck">
          <span class="dot"></span> 远程代理 DNS 解析
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'" @click="runHealthCheck">
          <span class="dot"></span> HTML5 物理定位禁用
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'" @click="runHealthCheck">
          <span class="dot"></span> Claude 客户端断网熔断
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'" @click="runHealthCheck">
          <span class="dot"></span> 美区时区锁定 (PST)
        </div>
      </section>

      <!-- 活跃连接审计流水表 (带过滤与 Claude 高亮) -->
      <section class="connections-table-card">
        <div class="panel-header">
          <div class="filter-group">
            <span class="panel-title">📋 实时数据连接审计日志</span>
            <div class="filter-tabs">
              <button 
                class="tab-btn" 
                :class="{ active: filterMode === 'all' }" 
                @click="filterMode = 'all'"
              >
                全部流量 ({{ connectionLogs.length }})
              </button>
              <button 
                class="tab-btn tab-claude" 
                :class="{ active: filterMode === 'claude' }" 
                @click="filterMode = 'claude'"
              >
                🟣 仅看 Claude ({{ claudeLogCount }})
              </button>
              <button 
                class="tab-btn" 
                :class="{ active: filterMode === 'active' }" 
                @click="filterMode = 'active'"
              >
                ⚡ 活跃连接 ({{ activeLogCount }})
              </button>
            </div>
          </div>

          <div class="action-buttons">
            <button class="clear-btn" @click="handleClearLogs" title="清空日志流水">
              🗑️ 清空日志
            </button>
          </div>
        </div>

        <div class="table-container">
          <table class="audit-table">
            <thead>
              <tr>
                <th>时间</th>
                <th>目标域名 / 端口</th>
                <th>协议方法</th>
                <th>数据流出 (Upload)</th>
                <th>数据流入 (Download)</th>
                <th>状态</th>
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
                  <span class="status-tag" :class="log.status === 'Active' ? 'tag-active' : (log.status === 'Blocked' ? 'tag-blocked' : 'tag-closed')">
                    {{ log.status === 'Active' ? '活跃会话' : (log.status === 'Blocked' ? '🛡️已拦截' : '已完成') }}
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

    <!-- 底部状态条 -->
    <footer class="app-footer">
      <span>{{ statusMessage }}</span>
      <span>Claude Stealth Mode · 零泄露工业级架构</span>
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
  background-color: #0b0f19;
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
  padding: 12px 24px;
  background-color: #0f172a;
  border-bottom: 1px solid #1e293b;
  gap: 16px;
}

.logo-area {
  display: flex;
  align-items: center;
  gap: 12px;
}

.shield-icon {
  font-size: 26px;
}

.title {
  margin: 0;
  font-size: 17px;
  font-weight: 700;
  letter-spacing: -0.02em;
  color: #ffffff;
}

.subtitle {
  margin: 2px 0 0 0;
  font-size: 11px;
  color: #64748b;
}

/* 节点探测条 */
.node-status-bar {
  display: flex;
  align-items: center;
  gap: 8px;
  background-color: rgba(30, 41, 59, 0.7);
  border: 1px solid #334155;
  padding: 4px 12px;
  border-radius: 20px;
  cursor: pointer;
  transition: all 0.2s ease;
}

.node-status-bar:hover {
  background-color: rgba(51, 65, 85, 0.8);
  border-color: #475569;
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}

.dot-green {
  background-color: #10b981;
  box-shadow: 0 0 6px #10b981;
}

.dot-yellow {
  background-color: #eab308;
  box-shadow: 0 0 6px #eab308;
}

.node-info-text {
  font-size: 12px;
  color: #cbd5e1;
  font-family: monospace;
}

.mini-btn {
  background: transparent;
  border: none;
  color: #38bdf8;
  font-size: 11px;
  cursor: pointer;
  padding: 0 2px;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 12px;
}

.health-check-btn {
  background-color: rgba(30, 41, 59, 0.8);
  border: 1px solid #334155;
  color: #38bdf8;
  padding: 6px 14px;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.health-check-btn:hover {
  background-color: #1e293b;
  border-color: #38bdf8;
}

.status-badge {
  padding: 6px 14px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
}

.badge-safe {
  background-color: rgba(16, 185, 129, 0.15);
  color: #10b981;
  border: 1px solid rgba(16, 185, 129, 0.4);
}

.badge-idle {
  background-color: rgba(148, 163, 184, 0.1);
  color: #94a3b8;
  border: 1px solid rgba(148, 163, 184, 0.2);
}

.toggle-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 7px 18px;
  border-radius: 6px;
  font-weight: 600;
  font-size: 13px;
  border: none;
  cursor: pointer;
  transition: all 0.2s ease;
}

.btn-primary {
  background-color: #2563eb;
  color: white;
}

.btn-primary:hover {
  background-color: #1d4ed8;
}

.btn-danger {
  background-color: #e11d48;
  color: white;
}

.btn-danger:hover {
  background-color: #be123c;
}

.toggle-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

/* 主内容区 */
.dashboard-content {
  flex: 1;
  padding: 16px 24px;
  display: flex;
  flex-direction: column;
  gap: 14px;
  overflow-y: auto;
}

/* 流量卡片 */
.traffic-metrics-row {
  display: grid;
  grid-template-columns: 1fr 1fr 1.1fr;
  gap: 14px;
}

.metric-card {
  background-color: #111827;
  border: 1px solid #1f2937;
  border-radius: 10px;
  padding: 14px 18px;
}

.card-inflow {
  border-left: 4px solid #10b981;
}

.card-outflow {
  border-left: 4px solid #f43f5e;
}

.card-gateway {
  border-left: 4px solid #38bdf8;
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.metric-label {
  font-size: 13px;
  font-weight: 600;
  color: #94a3b8;
}

.metric-tag {
  font-size: 11px;
  padding: 2px 6px;
  border-radius: 4px;
  background-color: #1e293b;
  color: #64748b;
}

.metric-value {
  font-size: 26px;
  font-weight: 700;
  font-family: monospace;
}

.text-emerald {
  color: #10b981;
}

.text-rose {
  color: #f43f5e;
}

.text-sky {
  color: #38bdf8;
}

.metric-total {
  margin-top: 4px;
  font-size: 12px;
  color: #64748b;
}

.metric-total strong {
  color: #cbd5e1;
}

.gateway-info-row {
  display: flex;
  justify-content: space-between;
  font-size: 12px;
  color: #94a3b8;
  margin-top: 4px;
}

.upstream-tag {
  background-color: #1e293b;
  padding: 2px 6px;
  border-radius: 4px;
  cursor: pointer;
  color: #38bdf8;
  transition: all 0.2s;
}

.upstream-tag:hover {
  background-color: #334155;
  color: #ffffff;
}

/* 折线图 */
.chart-panel {
  background-color: #111827;
  border: 1px solid #1f2937;
  border-radius: 10px;
  padding: 12px 18px;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.panel-title {
  font-size: 13px;
  font-weight: 600;
  color: #e2e8f0;
}

.chart-legend {
  display: flex;
  gap: 14px;
  font-size: 12px;
}

.chart-wrapper {
  height: 60px;
  width: 100%;
}

.traffic-svg {
  width: 100%;
  height: 100%;
}

/* 防护指示标 */
.security-badges-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.badge-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 10px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s;
}

.badge-item:hover {
  transform: translateY(-1px);
}

.badge-on {
  background-color: rgba(16, 185, 129, 0.1);
  color: #34d399;
  border: 1px solid rgba(16, 185, 129, 0.25);
}

.badge-off {
  background-color: rgba(71, 85, 105, 0.15);
  color: #64748b;
  border: 1px solid rgba(71, 85, 105, 0.2);
}

.dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background-color: currentColor;
}

/* 审计列表 */
.connections-table-card {
  flex: 1;
  background-color: #111827;
  border: 1px solid #1f2937;
  border-radius: 10px;
  padding: 12px 18px;
  display: flex;
  flex-direction: column;
  min-height: 180px;
}

.filter-group {
  display: flex;
  align-items: center;
  gap: 14px;
}

.filter-tabs {
  display: flex;
  gap: 6px;
}

.tab-btn {
  background-color: #1e293b;
  border: 1px solid #334155;
  color: #94a3b8;
  padding: 4px 10px;
  border-radius: 4px;
  font-size: 11px;
  cursor: pointer;
  transition: all 0.2s;
}

.tab-btn:hover {
  background-color: #334155;
  color: #ffffff;
}

.tab-btn.active {
  background-color: #2563eb;
  border-color: #2563eb;
  color: #ffffff;
}

.tab-btn.tab-claude.active {
  background-color: #7c3aed;
  border-color: #7c3aed;
}

.clear-btn {
  background-color: transparent;
  border: 1px solid #334155;
  color: #94a3b8;
  padding: 4px 10px;
  border-radius: 4px;
  font-size: 11px;
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
  margin-top: 8px;
}

.audit-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.audit-table th {
  text-align: left;
  padding: 6px 10px;
  color: #64748b;
  border-bottom: 1px solid #1e293b;
  font-weight: 500;
}

.audit-table td {
  padding: 6px 10px;
  border-bottom: 1px solid #111e32;
  color: #cbd5e1;
}

.row-claude {
  background-color: rgba(124, 58, 237, 0.08);
}

.claude-badge {
  background-color: #7c3aed;
  color: white;
  font-size: 10px;
  padding: 1px 5px;
  border-radius: 3px;
  margin-right: 6px;
  font-weight: 600;
}

.col-time {
  color: #64748b;
  font-family: monospace;
}

.col-host {
  font-weight: 500;
  max-width: 280px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.method-tag {
  background-color: #1e293b;
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 10px;
  color: #94a3b8;
  font-family: monospace;
}

.status-tag {
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 10px;
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
  padding: 30px;
  color: #475569;
}

/* 底部状态 */
.app-footer {
  display: flex;
  justify-content: space-between;
  padding: 6px 20px;
  background-color: #0b0f19;
  border-top: 1px solid #1e293b;
  font-size: 11px;
  color: #64748b;
}

/* 弹窗 Modal */
.modal-backdrop {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.7);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
}

.modal-content {
  background-color: #0f172a;
  border: 1px solid #334155;
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
  padding: 14px 20px;
  border-bottom: 1px solid #1e293b;
}

.modal-title-area h3 {
  margin: 0;
  font-size: 15px;
  color: #ffffff;
}

.modal-grade {
  display: inline-block;
  margin-top: 4px;
  font-size: 11px;
  padding: 2px 8px;
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
  font-size: 18px;
  cursor: pointer;
}

.modal-body {
  padding: 14px 20px;
  overflow-y: auto;
  max-height: 480px;
}

.modal-loading {
  text-align: center;
  padding: 30px;
  color: #38bdf8;
  font-size: 13px;
}

.check-items-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.check-item-row {
  display: flex;
  align-items: center;
  padding: 8px 12px;
  border-radius: 6px;
  background-color: #1e293b;
  border: 1px solid #334155;
}

.check-pass {
  border-left: 3px solid #10b981;
}

.check-fail {
  border-left: 3px solid #eab308;
}

.check-icon {
  font-size: 16px;
  margin-right: 12px;
}

.check-info {
  flex: 1;
}

.check-title {
  font-size: 13px;
  font-weight: 600;
  color: #f1f5f9;
}

.check-desc {
  font-size: 11px;
  color: #94a3b8;
  margin-top: 2px;
}

.check-status-tag {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: 4px;
  background-color: rgba(15, 23, 42, 0.6);
  color: #cbd5e1;
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  padding: 12px 20px;
  border-top: 1px solid #1e293b;
  background-color: #0b0f19;
  border-bottom-left-radius: 12px;
  border-bottom-right-radius: 12px;
}

.modal-action-btn {
  background-color: #2563eb;
  color: white;
  border: none;
  padding: 6px 14px;
  border-radius: 6px;
  font-size: 12px;
  cursor: pointer;
}

.modal-close-btn {
  background-color: #334155;
  color: white;
  border: none;
  padding: 6px 14px;
  border-radius: 6px;
  font-size: 12px;
  cursor: pointer;
}

.spinner {
  display: inline-block;
  width: 12px;
  height: 12px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-radius: 50%;
  border-top-color: white;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>
