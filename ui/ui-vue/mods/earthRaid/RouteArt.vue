<template>
  <!-- El dibujo de un tramo como las tarjetas del modo rally del juego: línea roja, salida y meta en círculos -->
  <svg class="route-art" :viewBox="`0 0 ${W} ${H}`" role="img">
    <rect x="1" y="1" :width="W - 2" :height="H - 2" rx="10" class="frame" />
    <polyline v-if="pts.length" :points="pts.map(p => p.join(',')).join(' ')" class="halo" />
    <polyline v-if="pts.length" :points="pts.map(p => p.join(',')).join(' ')" class="road" :class="tone" />
    <g v-if="pts.length">
      <circle :cx="pts[0][0]" :cy="pts[0][1]" r="7" class="dot-start" />
      <g :transform="`translate(${pts[pts.length - 1][0]},${pts[pts.length - 1][1]})`">
        <circle r="7.5" class="dot-finish" />
        <rect x="-4" y="-4" width="4" height="4" class="chk" /><rect x="0" y="0" width="4" height="4" class="chk" />
      </g>
    </g>
  </svg>
</template>

<script setup>
import { computed } from "vue"
const props = defineProps({ outline: { type: [Array, Object], default: () => [] }, tone: { type: String, default: "red" } })
const W = 160, H = 120, PAD = 16
const list = v => (Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : [])
const pts = computed(() => {
  const o = list(props.outline).map(p => list(p))
  if (o.length < 2) return []
  let a = Infinity, b = Infinity, c = -Infinity, d = -Infinity
  for (const p of o) { a = Math.min(a, p[0]); b = Math.min(b, p[1]); c = Math.max(c, p[0]); d = Math.max(d, p[1]) }
  const k = Math.cos(((a + c) / 2) * Math.PI / 180)
  const w = Math.max((d - b) * k, 1e-6), h = Math.max(c - a, 1e-6)
  const sc = Math.min((W - 2 * PAD) / w, (H - 2 * PAD) / h)
  const ox = (W - w * sc) / 2, oy = (H - h * sc) / 2
  return o.map(p => [+(ox + (p[1] - b) * k * sc).toFixed(1), +(oy + (c - p[0]) * sc).toFixed(1)])
})
</script>

<style scoped lang="scss">
.route-art { display: block; width: 100%; height: 100%; }
.frame { fill: #2a2a2a; stroke: #e8e8e8; stroke-width: 2; }
.halo { fill: none; stroke: #1b1b1b; stroke-width: 8; stroke-linejoin: round; stroke-linecap: round; }
.road { fill: none; stroke: #e0393e; stroke-width: 4.5; stroke-linejoin: round; stroke-linecap: round; }
.road.blue { stroke: #2f8fe0; }
.dot-start { fill: #fff; stroke: #111; stroke-width: 2.5; }
.dot-finish { fill: #fff; stroke: #111; stroke-width: 2.5; }
.chk { fill: #111; }
</style>
