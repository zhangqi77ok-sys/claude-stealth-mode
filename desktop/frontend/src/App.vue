<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { EventsOn } from '../wailsjs/runtime/runtime'
import { GetStatus, GetTrafficNow, ToggleStealth } from '../wailsjs/go/main/App'

// 状态数据
const isProtected = ref(false)
const isLoading = ref(false)
const statusMessage = ref('网关正在监听 127.0.0.1:8999')

// 流量数据
const speedIn = ref(0)       // Bytes/s
const speedOut = ref(0)      // Bytes/s
const totalIn = ref(0)       // Bytes
const totalOut = ref(0)      // Bytes
const activeConns = ref(0)
const connectionLogs = ref([])

// 实时折线图历史点 (最近 30 秒)
const historyIn = ref(new Array(30).fill(0))
const historyOut = ref(new Array(30).fill(0))

// 格式化函数
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

// 切换防护模式
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

// 刷新状态检测
async function refreshStatus() {
  try {
    const res = await GetStatus()
    if (res) {
      isProtected.value = res.isProtected
    }
  } catch {}
}

// 接收来自 Go 端的每秒推流数据
function handleTrafficUpdate(data) {
  if (!data) return
  speedIn.value = data.speedIn || 0
  speedOut.value = data.speedOut || 0
  totalIn.value = data.totalIn || 0
  totalOut.value = data.totalOut || 0
  activeConns.value = data.activeConns || 0

  if (data.logs && Array.isArray(data.logs)) {
    connectionLogs.value = data.logs.slice().reverse()
  }

  // 更新历史折线队列
  historyIn.value.push(data.speedIn || 0)
  historyIn.value.shift()

  historyOut.value.push(data.speedOut || 0)
  historyOut.value.shift()
}

// 计算 SVG 折线路径
const svgPathIn = computed(() => makeSvgPath(historyIn.value, '#10b981'))
const svgPathOut = computed(() => makeSvgPath(historyOut.value, '#f43f5e'))

function makeSvgPath(dataArr) {
  const max = Math.max(...dataArr, 1024) // 最小基准 1KB
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

  // 1. 注册 Wails 事件推流
  try {
    EventsOn('traffic-tick', (data) => {
      handleTrafficUpdate(data)
    })
  } catch (e) {
    console.error('EventsOn error:', e)
  }

  // 2. 双保险：启动 1 秒心跳主动轮询，确保与网关真实吞吐 100% 同步
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

      <div class="header-right">
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
      <!-- 流量监控大卡片 (流入 / 流出) -->
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
              <span>127.0.0.1:7897 (Clash)</span>
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
            <!-- 网格线 -->
            <line x1="0" y1="20" x2="600" y2="20" stroke="#1e293b" stroke-dasharray="3,3" />
            <line x1="0" y1="50" x2="600" y2="50" stroke="#1e293b" stroke-dasharray="3,3" />
            <line x1="0" y1="80" x2="600" y2="80" stroke="#1e293b" stroke-dasharray="3,3" />
            
            <!-- 流入流出路径 -->
            <path :d="svgPathIn" fill="none" stroke="#10b981" stroke-width="2.5" />
            <path :d="svgPathOut" fill="none" stroke="#f43f5e" stroke-width="2.5" />
          </svg>
        </div>
      </section>

      <!-- 10 项防护健康指示标 -->
      <section class="security-badges-bar">
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'">
          <span class="dot"></span> IPv6 旁路封堵
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'">
          <span class="dot"></span> WebRTC STUN 隔离
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'">
          <span class="dot"></span> Windows 多宿主 DNS 封堵
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'">
          <span class="dot"></span> QUIC (UDP 443) 禁用
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'">
          <span class="dot"></span> 远程代理 DNS 解析
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'">
          <span class="dot"></span> HTML5 物理定位禁用
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'">
          <span class="dot"></span> Claude 客户端断网熔断
        </div>
        <div class="badge-item" :class="isProtected ? 'badge-on' : 'badge-off'">
          <span class="dot"></span> 美区时区锁定 (PST)
        </div>
      </section>

      <!-- 活跃连接审计流水表 (流入流出详情) -->
      <section class="connections-table-card">
        <div class="panel-header">
          <span class="panel-title">📋 实时数据连接审计日志 (Active Connections)</span>
          <span class="badge-count">已记录 {{ connectionLogs.length }} 条记录</span>
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
              <tr v-for="log in connectionLogs" :key="log.id">
                <td class="col-time">{{ log.time }}</td>
                <td class="col-host">{{ log.host }}</td>
                <td><span class="method-tag">{{ log.method }}</span></td>
                <td class="text-rose font-mono">↑ {{ formatBytes(log.bytesOut) }}</td>
                <td class="text-emerald font-mono">↓ {{ formatBytes(log.bytesIn) }}</td>
                <td>
                  <span class="status-tag" :class="log.status === 'Active' ? 'tag-active' : (log.status === 'Blocked' ? 'tag-blocked' : 'tag-closed')">
                    {{ log.status === 'Active' ? '活跃连接' : (log.status === 'Blocked' ? '🛡️已拦截' : '已完成') }}
                  </span>
                </td>
              </tr>
              <tr v-if="connectionLogs.length === 0">
                <td colspan="6" class="empty-state">网关运行中，尚未捕获到连接请求（当通过本网关访问网络时将自动实时罗列）</td>
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
}

/* 顶部导航 */
.app-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px 24px;
  background-color: #0f172a;
  border-bottom: 1px solid #1e293b;
}

.logo-area {
  display: flex;
  align-items: center;
  gap: 12px;
}

.shield-icon {
  font-size: 28px;
}

.title {
  margin: 0;
  font-size: 18px;
  font-weight: 700;
  letter-spacing: -0.3px;
  color: #f8fafc;
}

.subtitle {
  margin: 2px 0 0;
  font-size: 12px;
  color: #94a3b8;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 16px;
}

.status-badge {
  padding: 6px 12px;
  border-radius: 9999px;
  font-size: 13px;
  font-weight: 600;
}

.badge-safe {
  background-color: rgba(16, 185, 129, 0.15);
  color: #10b981;
  border: 1px solid rgba(16, 185, 129, 0.3);
}

.badge-idle {
  background-color: rgba(148, 163, 184, 0.1);
  color: #94a3b8;
  border: 1px solid rgba(148, 163, 184, 0.2);
}

.toggle-btn {
  padding: 8px 20px;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  border: none;
  transition: all 0.2s;
}

.btn-primary {
  background-color: #0284c7;
  color: #ffffff;
}

.btn-primary:hover {
  background-color: #0369a1;
}

.btn-danger {
  background-color: #e11d48;
  color: #ffffff;
}

.btn-danger:hover {
  background-color: #be123c;
}

/* 核心仪表盘布局 */
.dashboard-content {
  flex: 1;
  padding: 18px 24px;
  display: flex;
  flex-direction: column;
  gap: 14px;
  overflow-y: auto;
}

/* 流量卡片三列排布 */
.traffic-metrics-row {
  display: grid;
  grid-template-columns: 1fr 1fr 1.2fr;
  gap: 14px;
}

.metric-card {
  background-color: #131d33;
  border: 1px solid #1e293b;
  border-radius: 12px;
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 12px;
  color: #94a3b8;
}

.metric-tag {
  background-color: #1e293b;
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 11px;
}

.metric-main {
  margin-top: 10px;
}

.metric-value {
  font-size: 26px;
  font-weight: 800;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
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
  margin-top: 4px;
  color: #94a3b8;
}

/* 实时图表面板 */
.chart-panel {
  background-color: #131d33;
  border: 1px solid #1e293b;
  border-radius: 12px;
  padding: 12px 16px;
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
  color: #cbd5e1;
}

.chart-legend {
  display: flex;
  gap: 12px;
  font-size: 11px;
}

.chart-wrapper {
  height: 85px;
  width: 100%;
}

.traffic-svg {
  width: 100%;
  height: 100%;
}

/* 防护标志栏 */
.security-badges-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.badge-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 10px;
  border-radius: 6px;
  font-size: 11px;
  border: 1px solid #1e293b;
  background-color: #0f172a;
}

.badge-on {
  color: #38bdf8;
  border-color: rgba(56, 189, 248, 0.3);
}

.badge-on .dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background-color: #38bdf8;
  box-shadow: 0 0 6px #38bdf8;
}

.badge-off {
  color: #64748b;
}

.badge-off .dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background-color: #64748b;
}

/* 连接日志表格 */
.connections-table-card {
  flex: 1;
  background-color: #131d33;
  border: 1px solid #1e293b;
  border-radius: 12px;
  padding: 12px 16px;
  display: flex;
  flex-direction: column;
  min-height: 160px;
}

.badge-count {
  font-size: 11px;
  color: #64748b;
}

.table-container {
  flex: 1;
  overflow-y: auto;
  margin-top: 6px;
}

.audit-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
  text-align: left;
}

.audit-table th {
  padding: 8px;
  color: #94a3b8;
  border-bottom: 1px solid #1e293b;
  font-weight: 500;
}

.audit-table td {
  padding: 8px;
  border-bottom: 1px solid #0f172a;
  color: #e2e8f0;
}

.col-time {
  color: #64748b;
  font-family: monospace;
}

.col-host {
  font-weight: 600;
  color: #f8fafc;
}

.method-tag {
  background-color: #1e293b;
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 10px;
  font-family: monospace;
}

.status-tag {
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 10px;
}

.tag-active {
  background-color: rgba(56, 189, 248, 0.2);
  color: #38bdf8;
}

.tag-closed {
  background-color: rgba(148, 163, 184, 0.1);
  color: #94a3b8;
}

.tag-blocked {
  background-color: rgba(244, 63, 94, 0.2);
  color: #f43f5e;
}

.empty-state {
  text-align: center;
  color: #64748b;
  padding: 24px 0;
}

/* 颜色工具 */
.text-emerald { color: #10b981; }
.text-rose { color: #f43f5e; }
.text-sky { color: #38bdf8; }
.font-mono { font-family: ui-monospace, monospace; }

/* 底部状态条 */
.app-footer {
  display: flex;
  justify-content: space-between;
  padding: 6px 24px;
  background-color: #0f172a;
  border-top: 1px solid #1e293b;
  font-size: 11px;
  color: #64748b;
}

.spinner {
  display: inline-block;
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top-color: #ffffff;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>
