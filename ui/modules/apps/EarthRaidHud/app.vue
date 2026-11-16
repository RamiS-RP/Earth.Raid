<template>
  <div class="erh-root" ref="root">
  <!-- Rally completo: en la asistencia y los enlaces, como el panel de enlace del juego (reloj del evento, tu tiempo,
       instrucciones), la tarjeta del siguiente control y el carnet de ruta -->
  <div class="erh rally" v-if="r && r.active && r.phase !== 'stage'">
    <div class="rbar">
      <div class="rcell"><div class="rlab">{{ t.eventClock }}</div><div class="rclock mono">{{ hms(r.clock) }}</div></div>
      <div class="rcell"><div class="rlab">{{ t.yourTime }}</div><div class="rtime mono">{{ fmt(r.total || 0) }}</div></div>
      <div class="rcell grow"><div class="rlab">{{ t.instructions }}</div><div class="rins" v-html="instructions"></div></div>
    </div>
    <div v-if="r.next && r.phase !== 'finished'" class="rnext">
      <div class="row"><span class="tag blue">{{ r.next.label }}</span><span class="big mono">{{ dist(r.next.distM) }}</span></div>
      <div v-if="r.next.early" class="sub"><span class="tag yellow small">SLOW</span> {{ t.early }}</div>
      <div class="sub small">{{ r.next.stageTitle || t.service }} · {{ km(r.next.liaisonKm * 1000) }} · {{ r.next.minutes }} min<span v-if="!r.next.real"> · GPS</span></div>
      <div v-if="r.next.limitKmh" class="limit"><span>{{ t.limit }}</span><span class="plate mono">{{ r.next.limitKmh }}km/h</span></div>
    </div>
    <div v-if="r.phase !== 'finished'" class="tcard">
      <div class="tchead"><b>TIME CARD</b><span>{{ r.eventName }}</span></div>
      <div class="tctotal"><span>{{ t.totalTime }}</span><b class="mono">{{ fmt(r.total || 0) }}</b></div>
      <div class="tcrows">
        <div class="tchdr"><span></span><span>{{ t.due }}</span><span>{{ t.actual }}</span><span>{{ t.status }}</span></div>
        <template v-for="row in cardRows" :key="row.label">
          <div v-if="row.kind === 'tc'" class="tcrow" :class="{ cur: row.label === curLabel }">
            <span class="lbl">{{ row.label }}</span><span class="mono box">{{ hhmm(row.due) }}</span>
            <span class="mono box grey">{{ row.actual != null ? hhmm(row.actual) : '' }}</span>
            <span class="st" :class="row.status">{{ statusText(row) }}</span>
          </div>
          <div v-else class="tcrow ss">
            <span class="lbl">{{ row.label }}</span><span class="sst">{{ row.title }}</span>
            <span class="mono box yellow">{{ row.time != null ? fmt(row.time) : (row.startAt ? hhmm(row.startAt) : '') }}</span>
          </div>
        </template>
      </div>
      <div v-if="list(r.penalties).length" class="tcpen">
        <div class="tcpent"><b>{{ t.penalties }}</b><span>{{ t.total }} {{ penTotal }}s</span></div>
        <div v-for="(p, i) in list(r.penalties)" :key="i" class="tcpenr"><span>{{ p.label }} · {{ penWhy(p.why) }}</span><b>{{ p.s }}s</b></div>
      </div>
    </div>
    <div v-if="r.phase === 'finished'" class="card result">
      <div class="res-title">{{ t.rallyDone }}</div>
      <div class="res-title small">{{ r.eventName }}</div>
      <div class="res-time mono">{{ fmt(r.total || 0) }}</div>
      <div class="res-rows">
        <div><span>{{ t.stageTimes }}</span><b class="mono">{{ fmt(r.stageTimes || 0) }}</b></div>
        <div><span>{{ t.penalties }}</span><b class="mono" :class="{ red: penTotal > 0 }">{{ penTotal > 0 ? '+' + penTotal + 's' : '0s' }}</b></div>
      </div>
      <div v-if="r.newBest" class="newbest">{{ t.newBest }}</div>
    </div>
  </div>

  <!-- Ocupa la pantalla sin bloquear el ratón: la barra de tramo arriba a la izquierda y la tarjeta de fase arriba en el
       centro, como RallyStageTiming y RallyCountdown del juego -->
  <div class="erh" v-if="d && d.phase && d.phase !== 'idle' && d.phase !== 'hold'">
    <div class="bar">
      <div class="left">
        <div class="name">
          <span>{{ stageLabel }}</span>
          <span v-if="surfaceText" class="surf" :class="d.surface">{{ surfaceText }}</span>
        </div>
        <div class="clock" :class="{ done: d.phase === 'toStop' || d.phase === 'done', pen: d.penalty > 0 && running }">{{ clockText }}</div>
      </div>
      <div class="track">
        <div class="line">
          <div class="fill" :style="{ width: pct + '%' }"></div>
          <span class="mark start"></span>
          <span v-if="d.splitM" class="mark" :class="{ hit: d.splitTime }" :style="{ left: (100 * d.splitM / d.totalM) + '%' }"></span>
          <span class="mark end" :class="{ hit: finished }"></span>
        </div>
        <div class="labels">
          <span v-if="d.splitM" class="lab" :style="{ left: (100 * d.splitM / d.totalM) + '%' }">{{ km(d.splitM) }}</span>
          <span class="lab end">{{ km(d.totalM) }}</span>
        </div>
        <div v-if="d.splitTime || d.penalty > 0" class="splits">
          <template v-if="d.splitTime"><b>{{ t.splits }}</b> {{ km(d.splitM) }} <span class="mono">{{ fmt(d.splitTime) }}</span></template>
          <span v-if="d.penalty > 0" class="penb">+{{ d.penalty }}s {{ penaltyText }}</span>
        </div>
      </div>
    </div>

    <!-- tarjeta de fase, arriba en el centro -->
    <div v-if="d.phase === 'tc'" class="card">
      <div class="row"><span class="tag blue">TC</span><span class="big mono">{{ dist(d.distM) }}</span></div>
      <div class="sub">{{ t.tcSub }}</div>
      <div class="hint"><span class="key">⇧</span>+<span class="key">E</span> {{ t.tcSkip }}</div>
    </div>
    <div v-else-if="d.phase === 'approach'" class="card">
      <div class="row"><span class="tag blue">{{ plate }}</span><span class="big mono">{{ dist(d.distM) }}</span></div>
      <div class="sub">{{ t.goSub }}</div>
    </div>
    <div v-else-if="d.phase === 'staging'" class="card">
      <div class="row"><span class="tag" :class="d.staged ? 'green' : d.overLine ? 'red' : 'yellow'">{{ d.staged ? 'STAGED' : d.overLine ? 'STOP' : 'SLOW' }}</span><span class="big mono">{{ metres(d.distM) }}</span></div>
      <div class="sub">{{ d.staged ? t.staged : d.overLine ? t.overLine : t.stage }}</div>
      <div class="sub">{{ t.startIn }} <span class="pill mono">{{ mmss(d.stagingLeft) }}</span></div>
      <div v-if="d.tcTime != null" class="hint">TC {{ hhmm(d.tcTime) }} · {{ t.startAt }} {{ hhmm(d.startAt) }}</div>
      <div v-if="d.staged" class="hint"><span class="key">⇧</span>+<span class="key">E</span> {{ t.skip }}</div>
    </div>
    <div v-else-if="d.phase === 'toStop'" class="card">
      <div class="row"><span class="tag yellow">SLOW</span><span class="big mono">{{ dist(d.distM) }}</span></div>
      <div class="sub">{{ t.toStop }}</div>
    </div>
    <div v-else-if="d.phase === 'done'" class="card result">
      <div class="res-title">{{ t.finish }}</div>
      <div class="res-time mono">{{ fmt(d.time + d.penalty) }}</div>
      <div class="res-rows">
        <div><span>{{ t.stageTime }}</span><b class="mono">{{ fmt(d.time) }}</b></div>
        <div v-if="d.splitTime"><span>{{ t.split }} {{ km(d.splitM) }}</span><b class="mono">{{ fmt(d.splitTime) }}</b></div>
        <div><span>{{ t.pen }}</span><b class="mono" :class="{ red: d.penalty > 0 }">{{ d.penalty > 0 ? '+' + d.penalty + 's' : '0s' }}</b></div>
        <div v-if="d.best"><span>{{ t.best }}</span><b class="mono">{{ fmt(d.best) }}</b></div>
      </div>
      <div v-if="d.newBest" class="newbest">{{ t.newBest }}</div>
    </div>

    <!-- marco de la cámara del reloj (la imagen la pone el juego debajo) -->
    <div v-if="view.show" class="clockframe" :class="'c' + view.code" :style="frameStyle"></div>
  </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from "vue"
import { useBridge } from "@/bridge"
import { useEvents } from "@/services/events"

const { api } = useBridge()
const events = useEvents()
const d = ref(null)
const view = ref({ show: false })
const r = ref(null)
events.on("EarthRaidHud", data => {
  d.value = data
  // tamaño y opacidad de las notas visuales del juego (ajustes del jugador)
  if (data && data.notesScale) document.documentElement.style.setProperty("--er-notes-scale", String(data.notesScale))
  if (data && data.notesOpacity) document.documentElement.style.setProperty("--er-notes-opacity", String(data.notesOpacity))
})
events.on("EarthRaidRally", data => { r.value = data })
events.on("EarthRaidClockView", v => { view.value = v || { show: false } })
onMounted(() => {
  api.engineLua("if earthRaid_main and earthRaid_main.sendHud then earthRaid_main.sendHud() end")
})

const TEXT = {
  es: { goSub: "Ve a la salida del tramo: sigue el GPS.", stage: "Coloca el coche en la línea de salida.",
    staged: "Colocado en la línea de salida.", startIn: "Salida en", skip: "salir ya", toStop: "Detente en el control STOP.",
    finish: "TRAMO TERMINADO", stageTime: "Tiempo de tramo", split: "Parcial", pen: "Penalización", best: "Tu mejor tiempo",
    newBest: "¡Nuevo mejor tiempo!", splits: "PARCIAL", stageWord: "TRAMO", falseStart: "salida en falso",
    staging: "fuera de hora", recovery: "recuperación", asphalt: "ASFALTO", gravel: "TIERRA", snow: "NIEVE", mixed: "MIXTO",
    overLine: "Te has pasado de la línea: da marcha atrás.", tcSub: "Detente en el control horario para fichar.",
    tcSkip: "saltar el control", startAt: "salida", eventClock: "RELOJ DEL EVENTO", yourTime: "TU TIEMPO",
    instructions: "INSTRUCCIONES", limit: "Límite", totalTime: "TIEMPO TOTAL", due: "PREVISTA", actual: "REAL", status: "ESTADO",
    penalties: "PENALIZACIONES", total: "Total", late: "retraso", early: "Llegas pronto: espera a tu minuto o pulsa ⇧+E.",
    earlyWord: "adelanto", service: "Asistencia", rallyDone: "RALLY TERMINADO",
    stageTimes: "Tiempos de tramo", ok: "OK", lateS: "TARDE", earlyS: "PRONTO",
    insService: "Sales de la asistencia ({tc}) a las {t}. Pulsa {k} para salir ya.",
    insLiaison: "Llega a {tc} entre {a} y {b}. Penalización por cada minuto antes o después: {p}.",
    insEarly: "En {tc}: tu minuto es {a}. Espera, o pulsa {k} para adelantar el reloj.",
    insFinal: "Vuelve a la asistencia ({tc}) entre {a} y {b} para cerrar el rally.",
    insDone: "Rally terminado. {k} para cerrar." },
  en: { goSub: "Drive to the stage start: follow the GPS.", stage: "Stage vehicle at start line.",
    staged: "Staged at the start line.", startIn: "Start in", skip: "start now", toStop: "Stop at Stop Control.",
    finish: "STAGE COMPLETE", stageTime: "Stage time", split: "Split", pen: "Penalty", best: "Your best",
    newBest: "New best time!", splits: "SPLITS", stageWord: "STAGE", falseStart: "false start",
    staging: "late staging", recovery: "recovery", asphalt: "TARMAC", gravel: "GRAVEL", snow: "SNOW", mixed: "MIXED",
    overLine: "Past the line: reverse behind it.", tcSub: "Stop at the time control to check in.",
    tcSkip: "skip the control", startAt: "start", eventClock: "EVENT CLOCK", yourTime: "YOUR TIME",
    instructions: "INSTRUCTIONS", limit: "Limit", totalTime: "TOTAL TIME", due: "DUE", actual: "ACTUAL", status: "STATUS",
    penalties: "PENALTIES", total: "Total", late: "late", early: "Early: wait for your minute or press ⇧+E.",
    earlyWord: "early", service: "Service", rallyDone: "RALLY COMPLETE", stageTimes: "Stage times", ok: "OK",
    lateS: "LATE", earlyS: "EARLY",
    insService: "You leave the service park ({tc}) at {t}. Press {k} to leave now.",
    insLiaison: "Reach {tc} between {a} - {b}. Penalty for each minute early or late: {p}.",
    insEarly: "At {tc}: your minute is {a}. Wait, or press {k} to advance the clock.",
    insFinal: "Return to the service park ({tc}) between {a} - {b} to finish the rally.",
    insDone: "Rally complete. {k} to close." },
}
const t = computed(() => TEXT[(d.value && d.value.lang === "es") || (r.value && r.value.lang === "es") ? "es" : "en"])
const list = v => (Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : [])
const running = computed(() => d.value && d.value.phase === "running")
const finished = computed(() => d.value && (d.value.phase === "toStop" || d.value.phase === "done"))

const plate = computed(() => {
  const r = list(d.value && d.value.runs)
  return r.length ? "SS" + r[0] : "SD"
})
const stageLabel = computed(() => {
  const v = d.value
  if (!v) return ""
  const n = v.stageNumber && v.stageCount ? `${v.stageNumber} / ${v.stageCount}` : plate.value
  return `${t.value.stageWord} ${n} · ${v.title || ""}`
})
const surfaceText = computed(() => (d.value && d.value.surface ? t.value[d.value.surface] || d.value.surface : ""))
const pct = computed(() => {
  const v = d.value
  if (!v || !v.totalM) return 0
  return Math.max(0, Math.min(100, (100 * (v.along || 0)) / v.totalM))
})
function fmt(sec) {
  if (sec == null) return ""
  const m = Math.floor(sec / 60)
  const r = (sec - m * 60).toFixed(1).padStart(4, "0")
  return m > 0 ? m + ":" + r : sec.toFixed(1)
}
function mmss(sec) {
  const s = Math.max(0, Math.ceil(sec || 0))
  return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
}
const km = m => (m / 1000).toFixed(1) + "km"
const metres = m => (m == null ? "" : (m < 0 ? "-" : "") + Math.abs(m).toFixed(2) + "m")
const dist = m => (m == null ? "" : m < 1000 ? Math.round(m) + "m" : (m / 1000).toFixed(2) + "km")
const clockText = computed(() => {
  const v = d.value
  if (!v) return ""
  if (v.phase === "running" || v.phase === "toStop" || v.phase === "done") return fmt(v.time)
  if (v.phase === "countdown") return "--:--:--"
  return "0.0"
})
// ---- rally completo
function hhmm(sec) {
  if (sec == null) return ""
  const s = Math.floor(sec) % 86400
  return String(Math.floor(s / 3600)).padStart(2, "0") + ":" + String(Math.floor(s / 60) % 60).padStart(2, "0")
}
function hms(sec) {
  const s = Math.floor(sec || 0) % 86400
  return hhmm(s) + ":" + String(s % 60).padStart(2, "0")
}
const esc = v => String(v == null ? "" : v).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c])
const instructions = computed(() => {
  const v = r.value
  if (!v) return ""
  const tag = (cls, x) => `<span class="${cls}">${esc(x)}</span>`
  const key = tag("k", "⇧+E")
  const n = v.next
  let tpl = ""
  const vals = { k: key, p: tag("p", (v.penaltyPerMin || 10) + "s") }
  if (v.phase === "finished") tpl = t.value.insDone
  else if (v.phase === "service") { tpl = t.value.insService; vals.tc = tag("c", "TC0"); vals.t = tag("m", hhmm((v.startMin || 0) * 60)) }
  else if (n) {
    vals.tc = tag("c", n.label)
    vals.a = tag("m", hhmm(n.dueMin * 60))
    vals.b = tag("m", hhmm(n.dueMin * 60 + 60))
    tpl = n.early ? t.value.insEarly : n.final ? t.value.insFinal : t.value.insLiaison
  }
  return tpl.replace(/\{(\w+)\}/g, (_, k) => vals[k] || "")
})
const curLabel = computed(() => {
  const v = r.value
  if (!v) return null
  if (v.phase === "service") return "TC0"
  return v.next ? v.next.label : null
})
// el carnet entero no cabe en un rally de 13 tramos: la parte alrededor del control en curso
const cardRows = computed(() => {
  const rows = list(r.value && r.value.rows)
  const i = Math.max(0, rows.findIndex(x => x.label === curLabel.value))
  const from = Math.max(0, Math.min(i - 5, rows.length - 12))
  return rows.slice(from, from + 12)
})
const penTotal = computed(() => list(r.value && r.value.penalties).reduce((a, p) => a + (p.s || 0), 0))
const penWhy = w => (w === "early" ? t.value.earlyWord : t.value[w] || w)
function statusText(row) {
  if (!row.status) return ""
  if (row.status === "ok") return t.value.ok
  return (row.status === "late" ? t.value.lateS : t.value.earlyS) + (row.penalty ? " +" + row.penalty + "s" : "")
}

// agrupadas: "recuperación ×5" en vez de repetirla
const penaltyText = computed(() => {
  const n = {}
  list(d.value && d.value.penalties).forEach(p => { n[p.kind] = (n[p.kind] || 0) + 1 })
  return Object.keys(n).map(k => (t.value[k] || k) + (n[k] > 1 ? " ×" + n[k] : "")).join(", ")
})
// la ventana de la cámara viene en píxeles de la ventana del juego: a píxeles de la interfaz (que puede ir escalada) y
// relativos a esta app (que no empieza en 0,0)
const root = ref(null)
const frameStyle = computed(() => {
  const v = view.value
  const k = v.sw ? window.innerWidth / v.sw : 1 / (window.devicePixelRatio || 1)
  const r = root.value ? root.value.getBoundingClientRect() : { left: 0, top: 0 }
  return { left: v.x * k - r.left + "px", top: v.y * k - r.top + "px", width: v.w * k + "px", height: v.h * k + "px" }
})
</script>

<style scoped lang="scss">
.erh { position: absolute; inset: 0; pointer-events: none; color: #fff; font-family: inherit; z-index: 1; }
.mono { font-family: "Overpass Mono", "Roboto Mono", monospace; font-variant-numeric: tabular-nums; }
// barra de tramo (RallyStageTiming)
.bar { position: absolute; left: 0; top: 0; width: min(820px, 38vw); display: flex; background: rgba(26, 29, 34, 0.82); }
.left { display: flex; flex-direction: column; width: 250px; flex: none; }
.name { display: flex; align-items: center; gap: 10px; padding: 3px 9px 2px; font-size: 14px; font-style: italic; font-weight: 700;
  letter-spacing: 0.02em; text-transform: uppercase; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.surf { font-style: normal; font-size: 10px; padding: 0 5px; border-radius: 3px; background: #555c66; letter-spacing: 0.08em; }
.surf.asphalt { background: #4a4f57; }
.surf.gravel { background: #a8642c; }
.surf.snow { background: #6ba3c9; }
.clock { background: #0b9a22; padding: 1px 9px 2px; font-size: 32px; font-weight: 800; text-align: center; line-height: 1.12;
  font-variant-numeric: tabular-nums; }
.clock.done { background: #f5b301; color: #191400; }
.track { flex: 1; padding: 18px 22px 4px 12px; min-width: 0; position: relative; }
.line { position: relative; height: 3px; background: rgba(255, 255, 255, 0.9); }
.fill { position: absolute; left: 0; top: -1px; height: 5px; background: #17c936; }
.mark { position: absolute; top: -5px; width: 9px; height: 9px; margin-left: -5px; background: #1a1d22; border: 2px solid #fff; box-sizing: content-box; }
.mark.start { left: 0; background: #17c936; border-color: #17c936; }
.mark.end { left: 100%; }
.mark.hit { background: #17c936; }
.labels { position: relative; height: 18px; margin-top: 8px; font-size: 13px; font-weight: 700; font-variant-numeric: tabular-nums; }
.lab { position: absolute; transform: translateX(-50%); white-space: nowrap; }
.lab.end { left: 100%; transform: translateX(-90%); }
.splits { font-size: 12px; color: #d6dbe2; display: flex; gap: 18px; align-items: center; }
.splits b { font-weight: 800; color: #fff; }
.penb { color: #ff6a5c; font-weight: 700; }
// tarjeta (RallyCountdown)
.card { position: absolute; left: 50%; top: 110px; transform: translateX(-50%); min-width: 400px; padding: 10px 26px 12px;
  background: rgba(80, 86, 104, 0.78); border-radius: 8px; text-align: center; }
.row { display: flex; align-items: center; justify-content: center; gap: 40px; }
.tag { display: inline-block; padding: 1px 12px; border-radius: 6px; font-size: 44px; font-weight: 800; line-height: 1.15; }
.tag.yellow { background: #ffee00; color: #111; box-shadow: 0 0 18px rgba(255, 238, 0, 0.35); }
.tag.green { background: #17c936; color: #062b0d; }
.tag.blue { background: #1e88d6; }
.big { font-size: 44px; font-weight: 700; }
.sub { font-size: 21px; margin-top: 4px; }
.pill { display: inline-block; background: #c45fd6; border-radius: 6px; padding: 0 10px; font-weight: 800; }
.hint { margin-top: 8px; font-size: 18px; opacity: 0.85; }
.key { display: inline-block; min-width: 22px; padding: 0 5px; border: 1px solid #dfe3e8; border-radius: 4px; margin: 0 3px; }
.result { min-width: 460px; background: rgba(24, 27, 32, 0.94); border-top: 4px solid var(--bng-orange, #ff6600); }
.res-title { font-size: 22px; font-style: italic; font-weight: 800; letter-spacing: 0.06em; }
.res-time { font-size: 70px; font-weight: 800; color: #f5b301; line-height: 1.1; }
.res-rows { display: grid; gap: 4px; margin-top: 8px; font-size: 20px; text-align: left; }
.res-rows div { display: flex; justify-content: space-between; gap: 30px; border-bottom: 1px solid rgba(255, 255, 255, 0.08); padding: 2px 0; }
.res-rows .red { color: #ff6a5c; }
.newbest { margin-top: 10px; display: inline-block; background: #17c936; color: #062b0d; font-weight: 800; padding: 3px 14px; border-radius: 4px; }
.clockframe { position: absolute; box-sizing: border-box; border: 6px solid #ff1e0f; }
.tag.red { background: #e3170a; color: #fff; }
.tag.small { font-size: 22px; padding: 0 8px; border-radius: 4px; vertical-align: middle; }
.sub.small { font-size: 18px; opacity: 0.85; }
// ---- rally completo: panel de enlace (como RallyDashboard), siguiente control (RallyCountdown) y carnet (Timecard)
.rbar { position: absolute; left: 0; right: 0; top: 0; display: flex; gap: 28px; align-items: stretch; padding: 8px 18px;
  background: rgba(40, 44, 52, 0.88); }
.rcell { display: flex; flex-direction: column; justify-content: center; }
.rcell.grow { flex: 1; min-width: 0; }
.rlab { font-size: 13px; letter-spacing: 0.1em; opacity: 0.75; font-weight: 700; }
.rclock { font-size: 34px; font-weight: 800; color: #ff5ad2; }
.rtime { font-size: 34px; font-weight: 800; }
.rins { font-size: 20px; line-height: 1.3; }
.rins :deep(.c) { background: #1e88d6; padding: 0 6px; border-radius: 3px; font-weight: 800; }
.rins :deep(.m) { color: #ff5ad2; font-weight: 800; }
.rins :deep(.p) { color: #ff5a4d; font-weight: 800; }
.rins :deep(.k) { border: 1px solid #dfe3e8; border-radius: 4px; padding: 0 5px; }
.rnext { position: absolute; right: 24px; top: 96px; min-width: 330px; padding: 12px 22px 14px; background: rgba(80, 86, 104, 0.9);
  border-radius: 8px; text-align: center; }
.rnext .row { gap: 26px; }
.rnext .tag, .rnext .big { font-size: 48px; }
.limit { margin-top: 8px; display: flex; gap: 12px; align-items: center; justify-content: center; font-size: 18px; }
.plate { background: #fff; color: #111; border: 3px solid #d0021b; border-radius: 6px; padding: 0 8px; font-weight: 800; font-size: 22px; }
.tcard { position: absolute; left: 14px; top: 96px; width: 430px; background: #f4f4f1; color: #1a1a1a; border-radius: 4px;
  box-shadow: 0 4px 18px rgba(0, 0, 0, 0.45); font-size: 15px; overflow: hidden; }
.tchead { display: flex; flex-direction: column; padding: 8px 12px 4px; }
.tchead b { font-size: 20px; letter-spacing: 0.08em; font-style: italic; }
.tchead span { font-size: 13px; opacity: 0.7; }
.tctotal { display: flex; justify-content: space-between; align-items: center; margin: 4px 12px 8px; padding: 4px 10px;
  background: #ffd84a; font-weight: 800; }
.tctotal b { font-size: 22px; }
.tcrows { padding: 0 12px 8px; display: grid; gap: 3px; }
.tchdr, .tcrow { display: grid; grid-template-columns: 62px 1fr 1fr 96px; gap: 6px; align-items: center; }
.tchdr { font-size: 11px; font-weight: 800; opacity: 0.6; letter-spacing: 0.06em; }
.tcrow .lbl { background: #1a1a1a; color: #fff; font-weight: 800; text-align: center; padding: 2px 0; border-radius: 2px; }
.tcrow.cur .lbl { background: #1e88d6; }
.tcrow .box { background: #fff; border: 1px solid #c9c9c4; text-align: center; padding: 1px 0; }
.tcrow .box.grey { background: #e2e2de; }
.tcrow .box.yellow { background: #ffe680; }
.tcrow.ss { grid-template-columns: 62px 1fr 112px; }
.tcrow .sst { font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tcrow .st { font-weight: 800; font-size: 13px; }
.tcrow .st.late, .tcrow .st.early { color: #d0021b; }
.tcpen { background: #fff6cf; padding: 6px 12px 8px; font-size: 13px; }
.tcpent { display: flex; justify-content: space-between; margin-bottom: 3px; }
.tcpenr { display: flex; justify-content: space-between; }
.res-title.small { font-size: 16px; font-style: normal; opacity: 0.8; }
.clockframe.cA { border-color: #ff9100; }
.clockframe.cG { border-color: #2bff00; }
</style>

<style lang="scss">
// la app de notas del juego (RallyVisualPacenotes): más pequeña y algo transparente, para no tapar la carretera
.pacenotes-app { opacity: var(--er-notes-opacity, 0.72); transform: scale(var(--er-notes-scale, 0.72)); transform-origin: top center; }
</style>
