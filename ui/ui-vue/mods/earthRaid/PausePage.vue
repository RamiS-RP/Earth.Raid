<template>
  <!-- Raid.Earth en el menú de pausa (Esc), con su propia pestaña como BeamNG.Earth y BeamMP: cada botón del lado
       muestra una de estas páginas en la tarjeta central; la tarjeta de la derecha es el estado del tramo -->
  <div class="erp" :class="'erp-' + page">
    <!-- tramo en marcha (tarjeta de la derecha) -->
    <template v-if="page === 'status'">
      <h3 class="erp-h"><span class="slash"></span>Raid.Earth</h3>
      <!-- rally completo: abandonar o reiniciar (desde el último TC o desde el principio) -->
      <template v-if="rallyOn">
        <div class="erp-run">
          <div class="dim small">{{ t("rallyRunning") }}</div>
          <b>{{ rallyOn.name }}</b>
          <div class="dim small" v-if="active">{{ active.title }}</div>
        </div>
        <BngButton :accent="ACCENTS.main" @click="call('uiRestartRally', true)">{{ t("restartFromTc") }}</BngButton>
        <BngButton :accent="ACCENTS.secondary" @click="call('uiRestartRally', false)">{{ t("restartRally") }}</BngButton>
        <BngButton :accent="ACCENTS.attention" @click="call('uiAbandon'); refresh()">{{ t("abandonRally") }}</BngButton>
      </template>
      <!-- tramo suelto: reiniciar o abandonar -->
      <template v-else-if="active">
        <div class="erp-run">
          <div class="dim small">{{ t("running") }}</div>
          <b>{{ active.title || active.stageId }}</b>
          <div class="dim small" v-if="activeEvent">{{ activeEvent.name }}</div>
        </div>
        <BngButton :accent="ACCENTS.main" @click="call('uiRestartStage')">{{ t("restartStage") }}</BngButton>
        <BngButton :accent="ACCENTS.attention" @click="call('uiAbandon'); refresh()">{{ t("abandonStage") }}</BngButton>
      </template>
      <p v-else class="dim">{{ t("pauseIdle") }}</p>
      <BngButton v-if="!active && !rallyOn" :accent="ACCENTS.main" @click="open()">{{ t("pauseOpen") }}</BngButton>
    </template>

    <!-- eventos -->
    <template v-else-if="page === 'events'">
      <h3 class="erp-h"><span class="slash"></span>{{ t("pauseEvents") }}</h3>
      <div v-if="!events.length" class="dim">{{ t("none") }}</div>
      <div class="erp-list">
        <button v-for="e in events" :key="e.id" class="erp-ev" @click="open(e.id)">
          <img v-if="e.logo" :src="e.logo" alt="" />
          <div v-else class="nologo">{{ (e.short || e.name || "").slice(0, 14) }}</div>
          <div class="erp-evinfo">
            <b>{{ e.name }}</b>
            <div class="dim small">{{ [e.city, e.championship, e.dates].filter(Boolean).join(" · ") }}</div>
            <div class="small">{{ e.stageCount || 0 }} {{ t("stagesShort") }} · {{ km(e.stageKm || 0) }}<template v-if="e.boxM != null"> · {{ dist(e.boxM) }}</template></div>
          </div>
        </button>
      </div>
    </template>

    <!-- importar -->
    <template v-else-if="page === 'import'">
      <h3 class="erp-h"><span class="slash"></span>{{ t("importTitle") }}</h3>
      <p class="dim">{{ t("pauseImport") }}</p>
      <BngButton :accent="ACCENTS.main" @click="openImport()">⤓ {{ t("newEvent") }}</BngButton>
    </template>

    <!-- ajustes -->
    <template v-else-if="page === 'settings'">
      <h3 class="erp-h"><span class="slash"></span>{{ t("settings") }}</h3>
      <div v-for="k in toggles" :key="k" class="erp-toggle" @click="toggle(k)">
        <span>{{ t(k) }}</span>
        <span class="tg" :class="{ on: set[k] }"><span class="knob"></span></span>
      </div>
      <p class="dim small">{{ t("pauseMore") }}</p>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { useEvents } from "@/services/events"
import { state, call, onState, list, t, km, dist } from "./store.js"

const props = defineProps({ page: { type: String, default: "events" } })
useEvents().on("EarthRaidState", m => onState(m))

const s = state
const events = computed(() => list(s.value && s.value.events))
const active = computed(() => s.value && s.value.stageActive)
const rallyOn = computed(() => s.value && s.value.rallyActive)
const activeEvent = computed(() => active.value && events.value.find(e => e.id === active.value.eventId))
const set = computed(() => (s.value && s.value.settings) || {})
const toggles = computed(() => {
  const k = ["hardcore", "visualNotes", "voice", "noTraffic", "regionalTraffic", "closures", "ambience", "parkCars", "sounds"]
  if (s.value && s.value.racingLineMod) k.push("racingLine")
  k.push("recModsAuto")
  return k
})

function refresh() { call("uiPeek") }
function open(id) { call("uiOpen"); if (id) call("uiSelect", id) }
function openImport() { call("uiOpen"); call("uiImportOpen", true) }
function toggle(k) { call("uiSetSetting", k, !set.value[k]) }
onMounted(refresh)
</script>

<style scoped lang="scss">
.erp { display: flex; flex-direction: column; gap: 10px; padding: 14px 16px; color: #fff; min-width: 0; }
.erp-h { display: flex; align-items: center; margin: 0 0 4px; font-size: 1.35em; font-style: italic; font-weight: 800; }
.slash { display: inline-block; width: 9px; height: 1.1em; background: #ff6600; transform: skewX(-18deg); margin-right: 10px; }
.dim { color: #a9a294; margin: 0; }
.small { font-size: 0.85em; }
.erp-run { display: flex; flex-direction: column; gap: 2px; padding: 8px 10px; border-left: 3px solid #ff6600; background: rgba(255, 255, 255, 0.05); }
.erp-list { display: flex; flex-direction: column; gap: 6px; max-height: 60vh; overflow-y: auto; }
.erp-ev {
  display: flex; align-items: center; gap: 12px; text-align: left; color: inherit; cursor: pointer;
  background: rgba(255, 255, 255, 0.04); border: 1px solid rgba(255, 255, 255, 0.08); border-radius: 6px; padding: 8px;
  &:hover, &:focus { border-color: #ff6600; background: rgba(255, 102, 0, 0.12); }
  img, .nologo { width: 120px; height: 56px; object-fit: contain; flex: 0 0 120px; }
  .nologo { display: flex; align-items: center; justify-content: center; background: #222; font-size: 0.8em; }
}
.erp-evinfo { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.erp-toggle { display: flex; justify-content: space-between; align-items: center; padding: 6px 2px; cursor: pointer; border-bottom: 1px solid rgba(255, 255, 255, 0.06); }
.tg { position: relative; width: 36px; height: 18px; border-radius: 9px; background: #555; flex: 0 0 36px;
  .knob { position: absolute; top: 2px; left: 2px; width: 14px; height: 14px; border-radius: 50%; background: #fff; transition: left 0.15s; }
  &.on { background: #ff6600; .knob { left: 20px; } } }
</style>
