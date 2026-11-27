<template>
  <!-- Earth.Raid: el mapa de la ficha del evento (petición del usuario, 19-nov: "un mapa estático marcando los tramos
       para tener una idea visual de por dónde están pasando"). Teselas del mapa de BeamNG.Earth (EOX terrain-light y
       su capa de rótulos; el navegador del juego no carga nada por http, así que se piden a su servidor como archivos
       en /temp, igual que hace su mapa del mundo), encima los tramos en rojo (el elegido en naranja), los enlaces en
       azul discontinuo, la salida y la meta de cada tramo con sus iconos. Fijo: ajustado para que quepa todo. -->
  <div ref="box" class="smap" :class="{ dark: dark }">
    <div class="tiles" v-if="view" :style="tileStyle">
      <template v-for="L in layers" :key="L">
        <!-- (v-if, no v-show: una imagen creada antes de que exista su archivo se queda rota en la caché del navegador) -->
        <template v-for="t in tiles" :key="L + ':' + t.key">
          <img v-if="ready[L] && ready[L].has(t.key)" class="tile" :class="{ overlay: L === 'labels' }"
               :src="`/temp/beamngEarth/maptiles/${L}/${t.key}.${L === 'labels' ? 'png' : 'jpg'}`"
               :style="{ left: t.left + 'px', top: t.top + 'px' }" draggable="false" @error="retry" />
        </template>
      </template>
    </div>
    <svg v-if="view" class="lines" :viewBox="`0 0 ${w} ${h}`">
      <!-- enlaces -->
      <polyline v-for="l in liaisonPts" :key="'l' + l.key" :points="l.pts" class="liaison" />
      <!-- tramos (el elegido, el último: encima) -->
      <template v-for="s in stagePts" :key="s.id">
        <polyline :points="s.pts" class="halo" :class="{ on: s.on }" />
        <polyline :points="s.pts" class="ss" :class="{ on: s.on, run: s.run, extra: s.extra, past: s.past }" />
        <polyline :points="s.pts" class="hit" @click="$emit('pick', s.id)" />
      </template>
      <template v-for="s in stagePts" :key="'m' + s.id">
        <g :transform="`translate(${s.a[0]},${s.a[1]})`" class="mk">
          <circle r="7" class="start" :class="{ on: s.on, past: s.past }" />
          <polygon points="-2.5,-4 3.5,0 -2.5,4" class="tri" />
        </g>
        <g :transform="`translate(${s.b[0]},${s.b[1]})`" class="mk">
          <rect x="-6.5" y="-6.5" width="13" height="13" rx="2" class="fin" />
          <rect x="-4.5" y="-4.5" width="4.5" height="4.5" class="chk" /><rect x="0" y="0" width="4.5" height="4.5" class="chk" />
        </g>
        <g v-if="s.on || stagePts.length <= 14" :transform="`translate(${s.a[0]},${s.a[1]})`" class="lbl">
          <rect x="10" y="-9" :width="s.plate.length * 7.4 + 8" height="17" rx="2" :class="{ on: s.on }" />
          <text x="14" y="4">{{ s.plate }}</text>
        </g>
      </template>
    </svg>
    <div class="credit">{{ credit }}</div>
    <div v-if="!view || !tilesReady" class="wait">{{ waitText }}</div>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue"
import { engineLua, list } from "./store.js"

const props = defineProps({
  stages: { type: [Array, Object], default: () => [] },
  liaisons: { type: [Array, Object], default: () => [] },
  pickId: { type: String, default: null },
  runId: { type: String, default: null },     // el tramo en marcha (verde)
  plate: { type: Function, default: s => s.id },
  dark: { type: Boolean, default: false },
  lang: { type: String, default: "es" },
  mode: { type: String, default: "stage" },      // "rally": solo los tramos del rally; "stage": todos
  fromRun: { type: [Number, String], default: null },   // salida desde este SS: los anteriores, en gris
})
defineEmits(["pick"])

const TILE = 256, PAD = 18, MAX_Z = 15, MIN_Z = 3
const box = ref(null)
const w = ref(0), h = ref(0)
const view = ref(null)            // { lat, lon, z }
const layers = ["map", "labels"]
const ready = ref({})             // capa -> Set de "z/x/y" que ya están en /temp
const credit = "© EOX IT Services (maps.eox.at) · © OpenStreetMap contributors"
const waitText = computed(() => (props.lang === "es" ? "Cargando el mapa…" : "Loading the map…"))

const pts = v => list(v).map(p => list(p)).filter(p => p.length >= 2 && isFinite(p[0]) && isFinite(p[1]))
// El papel de cada tramo en el mapa: del rally (rojo), fuera del rally (azul, solo en "tramo suelto") y ya recorrido
// porque se sale desde más adelante (gris). En "rally completo" solo se dibujan los del rally.
const inRally = s => list(s.runs).length > 0
const isPast = s => props.mode === "rally" && props.fromRun && list(s.runs).length > 0 && Math.max(...list(s.runs).map(Number)) < Number(props.fromRun)
const stList = computed(() => list(props.stages).filter(s => s && s.outline && (props.mode !== "rally" || inRally(s))))

// ---- Mercator
const R = TILE / (2 * Math.PI)
function project(lat, lon, z) {
  const n = 2 ** z
  const la = Math.max(-85.05, Math.min(85.05, lat)) * Math.PI / 180
  return [(lon + 180) / 360 * n * TILE, (1 - Math.log(Math.tan(la) + 1 / Math.cos(la)) / Math.PI) / 2 * n * TILE]
}
// la vista que mete todos los trazados en la caja
function fit() {
  if (!w.value || !h.value) return
  let a = Infinity, b = Infinity, c = -Infinity, d = -Infinity, n = 0
  const base = stList.value.filter(s => !isPast(s))
  for (const s of (base.length ? base : stList.value)) for (const p of pts(s.outline)) { a = Math.min(a, p[0]); b = Math.min(b, p[1]); c = Math.max(c, p[0]); d = Math.max(d, p[1]); n++ }
  if (!n) { view.value = null; return }
  const lat = (a + c) / 2, lon = (b + d) / 2
  // el zoom justo (con decimales: las teselas del nivel entero, escaladas)
  const p1 = project(a, b, 0), p2 = project(c, d, 0)
  const sw = Math.max(Math.abs(p2[0] - p1[0]), 1e-9), sh = Math.max(Math.abs(p2[1] - p1[1]), 1e-9)
  let z = Math.log2(Math.min((w.value - 2 * PAD) / sw, (h.value - 2 * PAD) / sh))
  z = Math.max(MIN_Z, Math.min(MAX_Z, z))
  view.value = { lat, lon, z, zi: Math.floor(z), scale: 2 ** (z - Math.floor(z)) }
}
const centre = computed(() => (view.value ? project(view.value.lat, view.value.lon, view.value.z) : null))
const centreI = computed(() => (view.value ? project(view.value.lat, view.value.lon, view.value.zi) : null))
const tileStyle = computed(() => (view.value ? { transform: `scale(${view.value.scale})`, transformOrigin: "center center" } : null))
function toScreen(lat, lon) {
  const c = centre.value, p = project(lat, lon, view.value.z)
  return [+(p[0] - c[0] + w.value / 2).toFixed(1), +(p[1] - c[1] + h.value / 2).toFixed(1)]
}
const tiles = computed(() => {
  if (!view.value) return []
  const c = centreI.value, z = view.value.zi, n = 2 ** z
  // (a nivel entero la vista es más pequeña: luego se escala)
  const hw = w.value / 2 / view.value.scale, hh = h.value / 2 / view.value.scale
  const x0 = Math.floor((c[0] - hw) / TILE), x1 = Math.floor((c[0] + hw) / TILE)
  const y0 = Math.floor((c[1] - hh) / TILE), y1 = Math.floor((c[1] + hh) / TILE)
  const out = []
  for (let y = Math.max(0, y0); y <= Math.min(n - 1, y1); y++) for (let x = x0; x <= x1; x++) {
    const xx = ((x % n) + n) % n
    out.push({ z, x: xx, y, key: `${z}/${xx}/${y}`, left: Math.round(x * TILE - c[0] + w.value / 2), top: Math.round(y * TILE - c[1] + h.value / 2) })
  }
  // las del centro primero (el servidor las hace en este orden)
  const cx = w.value / 2, cy = h.value / 2
  out.sort((p, q) => Math.hypot(p.left + 128 - cx, p.top + 128 - cy) - Math.hypot(q.left + 128 - cx, q.top + 128 - cy))
  return out
})
const tilesReady = computed(() => tiles.value.length > 0 && tiles.value.every(t => ready.value.map && ready.value.map.has(t.key)))

const stagePts = computed(() => {
  if (!view.value) return []
  const out = stList.value.map(s => {
    const o = pts(s.outline).map(p => toScreen(p[0], p[1]))
    if (o.length < 2) return null
    return { id: s.id, on: s.id === props.pickId, run: s.id === props.runId, extra: !inRally(s), past: isPast(s), pts: o.map(p => p.join(",")).join(" "), a: o[0], b: o[o.length - 1], plate: props.plate(s) }
  }).filter(Boolean)
  // el elegido al final: queda encima
  return out.sort((p, q) => (p.on ? 1 : 0) - (q.on ? 1 : 0))
})
const liaisonPts = computed(() => {
  if (!view.value) return []
  return list(props.liaisons).map((l, i) => ({ key: i, pts: pts(l.outline).map(p => toScreen(p[0], p[1])).map(p => p.join(",")).join(" ") })).filter(l => l.pts)
})

// ---- teselas: se piden a BeamNG.Earth (beamngEarth_settings.mapTiles) hasta que estén todas
let timer = null, gone = false
function ask() {
  timer = null
  if (gone || !view.value) return
  const missing = []
  for (const L of layers) for (const t of tiles.value) if (!(ready.value[L] && ready.value[L].has(t.key))) missing.push([t.z, t.x, t.y, L])
  if (!missing.length) return
  const lst = JSON.stringify(missing.slice(0, 64))
  engineLua(`beamngEarth_settings and beamngEarth_settings.mapTiles and beamngEarth_settings.mapTiles(jsonDecode('${lst}')) or {}`, r => {
    if (gone) return
    const next = { ...ready.value }
    for (const k of list(r)) {
      const i = String(k).indexOf("/")
      const L = String(k).slice(0, i), zxy = String(k).slice(i + 1)
      if (!layers.includes(L)) continue
      if (!next[L] || next[L] === ready.value[L]) next[L] = new Set(next[L] || [])
      next[L].add(zxy)
    }
    ready.value = next
  })
  timer = setTimeout(ask, 600)
}
// una tesela que falló (el archivo a medio escribir): se vuelve a pedir una vez, sin la caché
function retry(ev) {
  const i = ev && ev.target
  if (!i || i.dataset.retried) { if (i) i.style.visibility = "hidden"; return }
  i.dataset.retried = "1"
  setTimeout(() => { i.src = i.src.split("?")[0] + "?r=" + Date.now() }, 700)
}
function schedule() { if (timer) clearTimeout(timer); timer = setTimeout(ask, 50) }
watch(tiles, schedule)

let ro = null
function measure() {
  if (!box.value) return
  const r = box.value.getBoundingClientRect()
  if (Math.abs(r.width - w.value) > 1 || Math.abs(r.height - h.value) > 1) { w.value = Math.round(r.width); h.value = Math.round(r.height); fit() }
}
onMounted(() => {
  measure()
  if (window.ResizeObserver && box.value) { ro = new ResizeObserver(measure); ro.observe(box.value) }
})
onBeforeUnmount(() => { gone = true; if (timer) clearTimeout(timer); if (ro) ro.disconnect() })
watch([stList, () => list(props.liaisons).length, () => props.fromRun, () => props.mode], fit)
</script>

<style scoped lang="scss">
.smap { position: relative; width: 100%; height: 100%; min-height: 280px; overflow: hidden; background: #202328; border-radius: 4px; border: 1px solid rgba(255, 255, 255, 0.1); }
.tiles { position: absolute; inset: 0; }
.tile { position: absolute; width: 257px; height: 257px; pointer-events: none; }
.dark .tile:not(.overlay) { filter: invert(1) hue-rotate(180deg) brightness(0.78) saturate(0.55); }
.dark .tile.overlay { filter: invert(1) hue-rotate(180deg) brightness(1.15); }
.lines { position: absolute; inset: 0; width: 100%; height: 100%; }
polyline { fill: none; stroke-linejoin: round; stroke-linecap: round; }
.liaison { stroke: #d6dae0; stroke-width: 2.5; stroke-dasharray: 7 6; opacity: .85; }
.halo { stroke: rgba(0, 0, 0, .55); stroke-width: 7; }
.halo.on { stroke: #fff; stroke-width: 9; }
.ss { stroke: #e0393e; stroke-width: 3.5; }
.ss.extra { stroke: #2f8fe0; }
.ss.past { stroke: #8a8f98; opacity: .7; }
.ss.on { stroke: var(--bng-orange, #ff6600); stroke-width: 5; }
.ss.run { stroke: #17c936; }
.hit { stroke: transparent; stroke-width: 14; cursor: pointer; pointer-events: stroke; }
.mk { pointer-events: none; }
.start { fill: #17c936; stroke: #fff; stroke-width: 2; }
.start.on { fill: var(--bng-orange, #ff6600); }
.start.past { fill: #8a8f98; }
.tri { fill: #fff; }
.fin { fill: #fff; stroke: #111; stroke-width: 1.5; }
.chk { fill: #111; }
.lbl { pointer-events: none; }
.lbl rect { fill: rgba(20, 21, 24, .85); stroke: rgba(255, 255, 255, .25); }
.lbl rect.on { fill: var(--bng-orange, #ff6600); stroke: #fff; }
.lbl text { fill: #fff; font-size: 12px; font-weight: 800; font-style: italic; }
.credit { position: absolute; right: 4px; bottom: 2px; font-size: 10px; color: rgba(255, 255, 255, .75); background: rgba(0, 0, 0, .45); padding: 1px 6px; border-radius: 2px; pointer-events: none; }
.wait { position: absolute; left: 10px; top: 8px; font-size: 13px; font-style: italic; color: #cfd3d9; background: rgba(0, 0, 0, .5); padding: 3px 8px; border-radius: 3px; pointer-events: none; }
</style>
