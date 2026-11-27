<template>
  <!-- Earth.Raid: pantalla de carga al iniciar un tramo o un rally, copia del estilo de la del juego
       (ui-vue/src/common/modules/loading/views/LoadingScreen.vue): iconos que se rellenan de naranja de abajo arriba,
       barra inclinada, estado en cursiva, historial y barra de DATOS abajo. A la derecha, la imagen del evento. -->
  <!-- MARK:cover-v1 — aparece en 0,2 s (el juego no mueve nada hasta que tapa) y, mientras está (y mientras se va),
       las apps del juego (minimapa incluido) quedan ocultas: body.er-loading -->
  <Transition name="erl-fade" @after-leave="appsBack">
    <div v-if="ld && ld.on" class="erl-screen">
      <div class="erl-bg"></div>
      <div class="erl-right" v-if="ld.logo">
        <img :src="ld.logo" class="erl-img" alt="" />
      </div>
      <div class="erl-box">
        <div class="erl-event" v-if="ld.event">{{ ld.event }}</div>
        <div class="erl-icons">
          <div v-for="ic in iconRow" :key="ic.id" class="erl-icon" :style="{ backgroundPosition: `0 ${ic.p}%` }">
            <span class="erl-glyph">{{ ic.glyph }}</span>
          </div>
        </div>
        <div class="erl-bar"><div class="erl-fill" :style="{ width: Math.round((ld.progress || 0) * 100) + '%' }"></div></div>
        <div class="erl-status">{{ status }}</div>
        <div class="erl-title">{{ ld.title }}</div>
        <div class="erl-history">
          <div v-for="(h, i) in (ld.history || [])" :key="i">{{ h }}</div>
        </div>
      </div>
      <div class="erl-tips" v-if="ld.description">
        <div class="erl-tips-title">{{ es ? "DATOS" : "INFO" }}:</div>
        <div class="erl-tips-text">{{ ld.description }}</div>
      </div>
    </div>
  </Transition>
</template>

<script setup>
import { computed, onBeforeUnmount, ref } from "vue"
import { useEvents } from "@/services/events"
import { icons } from "@/common/components/base"

const ld = ref(null)
// las apps de pantalla fuera mientras hay pantalla de carga: vuelven cuando ha terminado de irse
const BODY_CLASS = "er-loading"
const STYLE_ID = "earthRaid-loading-style"
if (!document.getElementById(STYLE_ID)) {
  const st = document.createElement("style")
  st.id = STYLE_ID
  st.textContent = "body.er-loading .ui-apps-overlay, body.er-loading .app-uiapps-overlay-wrapper, " +
    "body.er-loading .ui-angular-app-slot { visibility: hidden !important; }"
  document.head.appendChild(st)
}
function appsBack() { document.body.classList.remove(BODY_CLASS) }
useEvents().on("EarthRaidLoading", d => {
  if (d && d.on) document.body.classList.add(BODY_CLASS)
  else if (!ld.value || !ld.value.on) appsBack()
  ld.value = d
})
onBeforeUnmount(appsBack)

const es = computed(() => !ld.value || ld.value.lang === "es")

// el primer icono que exista de cada lista (los nombres cambian entre versiones del juego)
function glyph(...names) {
  for (const n of names) if (icons && icons[n] && icons[n].glyph) return icons[n].glyph
  return "•"
}
const STEPS = [
  { id: "tp", glyph: glyph("lineToTerrain", "terrain", "globe") },
  { id: "roads", glyph: glyph("road", "roadStraight") },
  { id: "dress", glyph: glyph("mesh4Cells", "cube") },
  { id: "place", glyph: glyph("car", "carFront", "carStarter", "raceFlag") },
  { id: "settle", glyph: glyph("rallyHelmet", "raceFlag", "flag") },
]
const iconRow = computed(() => {
  const st = (ld.value && ld.value.icons) || {}
  // fondo al 200 %: 0 % = vacío, 100 % = lleno de naranja
  return STEPS.map(s => ({ ...s, p: st[s.id] || 0 }))
})

const TEXT = {
  es: { leave: "Un momento…", tp: "Viajando a la zona de salida…", roads: "Cargando carreteras…", dress: "Montando controles, salida y público…",
    place: "Colocando el coche…", settle: "Preparando la salida…" },
  en: { leave: "One moment…", tp: "Travelling to the start area…", roads: "Loading roads…", dress: "Setting up controls, start and crowd…",
    place: "Placing the car…", settle: "Getting ready…" },
}
const status = computed(() => (ld.value && (ld.value.status || TEXT[es.value ? "es" : "en"][ld.value.step])) || "")
</script>

<style scoped>
.erl-screen {
  position: fixed; inset: 0; z-index: 13000; background: #000; color: #fff; pointer-events: auto;
  font-family: "Overpass", var(--fnt-defs, sans-serif);
}
.erl-bg {
  position: absolute; inset: 0;
  background:
    radial-gradient(ellipse at 70% 45%, rgba(255, 255, 255, 0.10) 0%, rgba(0, 0, 0, 0) 55%),
    repeating-linear-gradient(115deg, rgba(255, 255, 255, 0.025) 0 2px, rgba(0, 0, 0, 0) 2px 90px),
    linear-gradient(180deg, #1b1b1d 0%, #0b0b0c 100%);
}
.erl-right {
  position: absolute; right: 6%; top: 12%; width: 46%; height: 58%;
  display: flex; align-items: center; justify-content: center;
}
.erl-img {
  max-width: 100%; max-height: 100%; object-fit: contain;
  filter: drop-shadow(0 18px 40px rgba(0, 0, 0, 0.8)) drop-shadow(0 0 30px rgba(255, 255, 255, 0.08));
}
.erl-box { position: absolute; top: 33%; left: 0; width: 32em; padding: 2em 5em 3em 5em; z-index: 2; }
.erl-event { color: #c8c8c8; font-size: 1.1em; margin-bottom: 0.4em; }
.erl-icons { display: flex; margin-left: -0.75em; }
.erl-icon {
  display: flex; align-items: center; justify-content: center;
  border: 2px solid #ff6600; border-radius: 10px; margin: 0.75em; padding: 0.25em; width: 3.5em; height: 3.5em;
  background: linear-gradient(0deg, #ff6600 0%, #ff6600 50%, rgba(0, 0, 0, 0) 50%);
  background-size: 200% 200%; background-origin: border-box; background-repeat: no-repeat;
  transition: background-position 0.35s ease;
}
.erl-glyph { font-family: "bngIcons" !important; font-size: 3em; line-height: 1em; color: #fff; font-weight: 100 !important; }
.erl-bar { overflow: hidden; height: 1.6em; margin-top: 0.4em; }
.erl-bar { transform: translateX(-1em) skewX(-23deg); background: rgba(255, 255, 255, 0.15); }
.erl-fill { height: 100%; background: linear-gradient(90deg, #ff8a00, #ff6600); transition: width 0.35s ease; }
.erl-status { min-height: 1em; font-style: italic; font-weight: 700; margin-top: 15px; font-size: 2em; }
.erl-title { font-style: italic; font-weight: 700; font-size: 1.3em; color: #ff8a3d; margin-top: 0.2em; }
.erl-history { margin-top: 1em; min-height: 5em; color: rgb(200, 200, 200); text-shadow: #000 0 0 12px, #000 0 0 6px; }
.erl-tips {
  position: absolute; left: 0; right: 0; bottom: 8%; display: flex; align-items: center; padding: 2em 5em 3em 5em;
  background-image: linear-gradient(220deg, rgba(0, 0, 0, 0.4) 0%, rgba(0, 0, 0, 0.65) 100%); z-index: 2;
}
.erl-tips-title { font-style: italic; font-size: 1.75em; font-weight: bold; }
.erl-tips-text { font-size: 1.125em; margin-left: 0.5em; max-width: 52em; }
.erl-fade-enter-active { transition: opacity 0.2s ease-out; }
.erl-fade-leave-active { transition: opacity 0.6s cubic-bezier(0.23, 1, 0.32, 1); }
.erl-fade-enter-from, .erl-fade-leave-to { opacity: 0; }
</style>
