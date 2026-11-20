<template>
  <!-- Raid.Earth: la pantalla de inicio, como la del modo rally del juego (MissionControl + MissionRallyInfo +
       MissionRallySettings): aparece tras la pantalla de carga, con el coche parado en el box de asistencia o antes
       del control horario, y el mundo detrás. Rally completo: resumen y normas a la izquierda, ajustes a la derecha;
       tramo suelto: una sola columna. Iniciar suelta el coche. Petición del usuario, 19-nov. -->
  <div class="ers" tabindex="-1" ref="rootEl" @keydown.esc.stop="back">
    <div class="card wide" v-if="pre && sel">
      <header class="head">
        <span class="slash"></span>
        <h1>{{ title }}</h1>
      </header>
      <nav class="tabs">
        <button class="navarrow" @click="back" :title="t('back')">‹</button>
        <button class="tab" :class="{ on: tab === 'info' }" @click="tab = 'info'" :title="t('summary')"><BngIcon :type="icons.roadInfo" class="ticon" /></button>
        <button class="tab" :class="{ on: tab === 'ratings' }" @click="tab = 'ratings'" :title="t('ratings')"><BngIcon :type="icons.chartBars" class="ticon" /></button>
        <div class="grow"></div>
      </nav>

      <div class="body two" v-if="tab === 'info'">
        <div class="col">
          <h2 class="sect"><span class="slash small"></span>{{ rally ? t("summary") : t("stageSummary") }}</h2>
          <template v-if="rally">
            <p class="desc" v-if="sel.description">{{ sel.description }}</p>
            <ul class="bul">
              <li>{{ t("stageDist", { d: km(sel.rallyStageKm != null ? sel.rallyStageKm : sel.stageKm) }) }}</li>
              <li>{{ t("liaisonDist", { d: km(sel.rallyLiaisonKm != null ? sel.rallyLiaisonKm : sel.liaisonKm) }) }}</li>
              <li v-if="sel.rallyKm">{{ t("totalDist", { d: km(sel.rallyKm) }) }}</li>
            </ul>
            <ul class="bul stages-bul">
              <li v-for="it in itinerary.filter(x => x.stageId)" :key="it.label"><b>SS{{ it.run }} {{ it.title }}</b> — {{ km(stageKm(it.stageId)) }} · {{ t(stageSurface(it.stageId)) }} 100%</li>
            </ul>
          </template>
          <template v-else-if="stage">
            <p class="desc">{{ stageDesc }}</p>
            <ul class="bul">
              <li>{{ t("distance") }}: {{ km(stage.km) }}</li>
              <li>{{ t("surface") }}: {{ t(stage.surface) }} 100%</li>
              <li v-if="stage.road">{{ t("roadLbl") }}: {{ stage.road }}</li>
              <li v-if="pre.reverse">{{ t("dirReverse") }}</li>
              <li v-if="stage.best" class="gold">{{ t("best") }}: {{ clock(stage.best) }}</li>
            </ul>
          </template>
          <h2 class="sect"><span class="slash small"></span>{{ t("rules") }}</h2>
          <ul class="bul">
            <li v-for="k in (rally ? ['ruleR1','ruleR2','ruleR3','ruleR4','rule2','rule3','rule4','rule5'] : ['rule1','rule2','rule3','rule4','rule5','rule6'])" :key="k">{{ t(k) }}</li>
          </ul>
        </div>
        <div class="col">
          <h2 class="sect"><span class="slash small"></span>{{ t("settings") }}</h2>
          <div class="settings"><SettingsBlock :rally="rally" /></div>
          <p class="dim small">{{ t("preNote") }}</p>
        </div>
      </div>

      <div class="body" v-else>
        <div class="col">
          <h2 class="sect"><span class="slash small"></span>{{ t("ratings") }}</h2>
          <table class="rtable">
            <thead><tr><th></th><th>{{ t("tries") }}</th><th>{{ t("best") }}</th><th>{{ t("last") }}</th></tr></thead>
            <tbody>
              <tr v-if="rally && sel.rallyRuns">
                <td><b>{{ t("rallyBest") }}</b></td><td class="mono">{{ sel.rallyRuns }}</td>
                <td class="mono gold">{{ clock(sel.rallyBest) }}</td><td></td>
              </tr>
              <tr v-for="st in (rally ? stages : stages.filter(x => stage && x.id === stage.id))" :key="st.id">
                <td><b>{{ plate(st) }}</b> {{ st.title }}</td>
                <td class="mono">{{ st.tries || 0 }}</td>
                <td class="mono gold">{{ clock(st.best) }}</td>
                <td class="mono small">{{ list(st.attempts).slice(0, 3).map(a => clock(a.total) + (a.penalty ? ' (+' + a.penalty + 's)' : '')).join('  ·  ') || '—' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <button class="go-btn" @click="go">{{ t("start") }}</button>
    </div>
  </div>
</template>

<script setup>
import { computed, defineComponent, h, onBeforeUnmount, onMounted, ref } from "vue"
import { useEvents } from "@/services/events"
import { BngIcon, icons } from "@/common/components/base"
import { state, call, onState, list, t, km, clock } from "./store.js"

useEvents().on("EarthRaidState", m => onState(m))
const rootEl = ref(null)
const s = state
const tab = ref("info")
let started = false
onMounted(() => { if (rootEl.value) rootEl.value.focus(); call("uiState") })
// cerrada sin Iniciar (Esc, otra pantalla): se deja el tramo, como al volver
onBeforeUnmount(() => { if (!started) call("uiPreLeft") })

const pre = computed(() => (s.value && s.value.pre) || null)
const sel = computed(() => (s.value && s.value.sel) || null)
const rally = computed(() => !!(pre.value && pre.value.kind === "rally"))
const stages = computed(() => list(sel.value && sel.value.stages))
const itinerary = computed(() => list(sel.value && sel.value.itinerary))
const stage = computed(() => stages.value.find(x => pre.value && x.id === pre.value.stageId) || null)
const title = computed(() => (rally.value ? sel.value.name : (stage.value ? plate(stage.value) + " " + stage.value.title : sel.value.name)))
const stageDesc = computed(() => {
  const st = stage.value
  if (!st) return ""
  const es = s.value && s.value.lang === "es"
  const k = String(st.kind || "")
  const kind = k === "ss" ? (es ? "Tramo cronometrado" : "Special stage") : /super|sss/i.test(k) ? (es ? "Superespecial" : "Super special stage") : /special|especial/i.test(k) ? (es ? "Tramo especial (fuera del rally)" : "Special stage (not in the rally)") : /sd|shake/i.test(k) ? "Shakedown" : /test|qual/i.test(k) ? (es ? "Test / calificación" : "Test / qualifying") : (es ? "Tramo" : "Stage")
  return `${kind} · ${sel.value.name}` + (list(st.runs).length > 1 ? (es ? ` · pasadas ${list(st.runs).join(" y ")}` : ` · runs ${list(st.runs).join(" and ")}`) : "")
})
// (las pasadas inversas llevan el id del tramo con R al final)
const byId = id => stages.value.find(y => y.id === id || y.id === String(id || "").replace(/R$/, ""))
function stageKm(id) { const x = byId(id); return x ? x.km : null }
function stageSurface(id) { const x = byId(id); return (x && x.surface) || "" }
function plate(st) { const r = list(st.runs); if (r.length) return "SS" + r.join("/"); const k = String(st.kind || ""); return /super|sss/i.test(k) ? "SSS" : /special|especial/i.test(k) ? (s.value && s.value.lang === "es" ? "ES" : "SP") : "SD" }
function go() { started = true; call("uiPreGo") }
function back() { started = true; call("uiPreBack") }

// ---- los ajustes (los que se pueden cambiar con el tramo ya montado: copiloto, notas, pantalla, sanciones; y en el
// rally, la media de los enlaces). Los que cambian el montaje (cortes, ambiente, flechas) están en Ajustes del menú.
const set = computed(() => (s.value && s.value.settings) || {})
const voices = computed(() => list(s.value && s.value.voicepacks))
const voice = computed(() => voices.value.find(v => v.id === set.value.voicepack) || voices.value[0] || { name: "—" })
function cycleVoice(dir) {
  const vs = voices.value
  if (!vs.length) return
  const i = Math.max(0, vs.findIndex(v => v.id === voice.value.id))
  call("uiSetSetting", "voicepack", vs[(i + dir + vs.length) % vs.length].id)
}
function toggle(k) { call("uiSetSetting", k, !set.value[k]) }
const SettingsBlock = defineComponent({
  props: { rally: Boolean },
  setup() {
    // en hardcore las ayudas no se pueden activar (se apagan solas)
    const AIDS = ["visualNotes", "racingLine"]
    const row = k => {
      const locked = set.value.hardcore && AIDS.includes(k)
      return h("div", { class: ["toggle-row", { locked }], key: k, onClick: () => { if (!locked) toggle(k) } }, [h("span", t(k)), h("span", { class: ["toggle", { on: set.value[k] }] }, [h("span", { class: "knob" })])])
    }
    const chips = (key, opts, label) => h("div", { class: "chips-row" }, opts.map(o => h("button", { key: o[0], class: ["chip", { on: set.value[key] === o[0] }], onClick: () => call("uiSetSetting", key, o[0]) }, label(o))))
    const group = (title, kids) => h("div", { class: "group" }, [h("div", { class: "glabel" }, title), ...kids])
    return () => {
      const v = voice.value
      const small = v.dialect || ""
      return h("div", [
        // el copiloto: la voz, cuándo canta, las notas en pantalla
        group(t("copilot"), [
          h("div", { class: "selector" }, [
            h("button", { onClick: () => cycleVoice(-1) }, "‹"),
            h("div", { class: "sel-val" }, [
              h("b", `${v.name} - ${v.style || ""}`),
              h("small", small + (v.partial ? " · " + t("vpPartial") : "")),
              h("div", { class: "dots" }, voices.value.map(x => h("span", { key: x.id, class: { on: x.id === v.id } }))),
            ]),
            h("button", { onClick: () => cycleVoice(1) }, "›"),
          ]),
          row("voice"),
          h("div", { class: "set-label" }, t("notesLead")),
          chips("notesLeadS", [[6, "early"], [4.5, "normal"], [3, "late"]], o => t(o[1])),
          row("visualNotes"),
          row("notesSafe"),
        ]),
        // la pantalla y las líneas
        ...(s.value && s.value.racingLineMod ? [group(t("screenLines"), [row("racingLine")])] : []),
        // las sanciones
        group(t("penalties"), [row("falseStart"), row("recoveryPenalty")]),
        // el modo de juego: hardcore
        group(t("modeGroup"), [row("hardcore"), h("p", { class: "dim small hcnote" }, t("hardcoreNote"))]),
      ])
    }
  },
})
</script>

<style scoped lang="scss">
.ers {
  --or: var(--bng-orange, #ff6600);
  --panel: rgba(18, 19, 22, 0.86);
  --panel2: rgba(40, 42, 48, 0.85);
  --ink: #f2f2f2;
  --dim: #a7abb3;
  --hair: rgba(255, 255, 255, 0.1);
  position: fixed; inset: 0; z-index: 50; color: var(--ink); outline: none; pointer-events: auto; font-size: 14.5px;
}
.card { position: absolute; left: 1.2vw; top: 1.5vh; bottom: 1.5vh; width: 400px; display: flex; flex-direction: column; background: var(--panel); border-radius: 6px; box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5); }
.card.wide { width: 860px; max-width: 96vw; }
.head { display: flex; align-items: center; padding: 12px 16px 4px; }
h1 { margin: 0; font-size: 30px; line-height: 1.1; font-style: italic; font-weight: 800; }
.slash { display: inline-block; width: 16px; height: 44px; background: var(--or); transform: skewX(-18deg); margin-right: 14px; flex: none; }
.slash.small { width: 8px; height: 20px; margin-right: 10px; }
.tabs { display: flex; align-items: center; gap: 6px; padding: 4px 16px 8px; border-bottom: 1px solid var(--hair); }
.navarrow { background: var(--panel2); border: 0; color: var(--ink); font-size: 24px; width: 40px; height: 40px; border-radius: 3px; cursor: pointer; }
.tab { width: 52px; height: 40px; background: transparent; border: 0; border-radius: 3px; color: var(--ink); font-size: 18px; cursor: pointer; }
.tab.on { background: var(--or); }
.ticon { width: 26px; height: 26px; color: #fff; fill: currentColor; }
.grow { flex: 1; }
.body { flex: 1; min-height: 0; overflow-y: auto; padding: 0 16px; }
.body.two { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
.sect { display: flex; align-items: center; margin: 14px 0 8px; font-size: 20px; font-style: italic; font-weight: 800; }
.desc { line-height: 1.4; color: #dcdfe4; margin: 0 0 6px; }
.bul { margin: 4px 0 10px; padding-left: 20px; line-height: 1.5; }
.stages-bul b { font-weight: 800; }
.dim { color: var(--dim); } .small { font-size: 12.5px; } .mono { font-variant-numeric: tabular-nums; } .gold { color: #f5c400; }
.go-btn { margin: 12px 16px 14px; padding: 13px; border: 0; border-radius: 3px; background: var(--or); color: #fff; font: inherit; font-size: 22px; font-weight: 800; font-style: italic; cursor: pointer; flex: none; }
.go-btn:hover { filter: brightness(1.1); }
.rtable { width: 100%; border-collapse: collapse; }
.rtable th { text-align: left; font-style: italic; color: var(--dim); padding: 6px 8px; border-bottom: 1px solid var(--hair); }
.rtable td { padding: 9px 8px; border-bottom: 1px solid var(--hair); }
// los ajustes (misma forma que en el menú)
.settings :deep(.set-label) { font-weight: 700; margin: 6px 0; }
.settings :deep(.group) { margin-bottom: 14px; padding-bottom: 6px; border-bottom: 1px solid var(--hair); }
.settings :deep(.glabel) { font-style: italic; font-weight: 800; color: var(--or); text-transform: uppercase; letter-spacing: .06em; font-size: 12.5px; margin: 2px 0 8px; }
.settings :deep(.selector) { display: grid; grid-template-columns: 40px 1fr 40px; align-items: center; background: #0f1013; border-radius: 4px; margin-bottom: 10px; }
.settings :deep(.selector button) { height: 60px; background: transparent; border: 0; color: var(--ink); font-size: 24px; cursor: pointer; }
.settings :deep(.selector button:hover) { color: var(--or); }
.settings :deep(.sel-val) { text-align: center; padding: 6px 0; }
.settings :deep(.sel-val small) { display: block; color: var(--dim); }
.settings :deep(.dots) { display: flex; gap: 4px; justify-content: center; margin-top: 6px; }
.settings :deep(.dots span) { width: 30px; height: 3px; background: #444; }
.settings :deep(.dots span.on) { background: var(--or); }
.settings :deep(.chips-row) { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 10px; }
.settings :deep(.chip) { display: inline-flex; align-items: center; padding: 4px 10px; border-radius: 3px; border: 1px solid var(--hair); background: var(--panel2); color: var(--ink); font: inherit; font-size: 13px; cursor: pointer; }
.settings :deep(.chip.on) { background: var(--or); border-color: var(--or); color: #fff; }
.settings :deep(.toggle-row) { display: flex; align-items: center; justify-content: space-between; padding: 10px 12px; margin-bottom: 4px; background: rgba(255,255,255,.04); border-radius: 3px; cursor: pointer; }
.settings :deep(.toggle-row:hover) { background: rgba(255,255,255,.08); }
.settings :deep(.toggle-row.locked) { opacity: .45; cursor: not-allowed; }
.settings :deep(.hcnote) { margin: 4px 2px 0; line-height: 1.35; }
.settings :deep(.toggle) { width: 34px; height: 16px; border-radius: 8px; background: #555; position: relative; flex: none; }
.settings :deep(.toggle .knob) { position: absolute; top: 2px; left: 2px; width: 12px; height: 12px; border-radius: 50%; background: #ddd; transition: left .15s; }
.settings :deep(.toggle.on) { background: var(--or); }
.settings :deep(.toggle.on .knob) { left: 20px; background: #fff; }
</style>
