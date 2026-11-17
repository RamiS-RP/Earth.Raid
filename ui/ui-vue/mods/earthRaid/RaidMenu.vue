<template>
  <div class="er" tabindex="-1" ref="rootEl" @keydown.esc.stop="escape">
    <!-- ===================== catálogo (como "Toda la jugabilidad") ===================== -->
    <template v-if="!sel">
      <div class="browser">
        <section class="main panel">
          <header class="ttl">
            <span class="slash"></span>
            <h1>{{ t("title") }} <span v-if="filtered" class="dim">{{ t("filtered") }}</span></h1>
            <div class="grow"></div>
            <form class="find" @submit.prevent>
              <input v-model="q" type="text" maxlength="60" :placeholder="t('search')" @keydown.stop @keyup.esc.stop="clearQ"
                     @input="typed" @focus="typing(true)" @blur="typing(false)" />
            </form>
            <button class="xbtn imp" @click="call('uiImportOpen', true)" :title="t('importTitle')">⤓ {{ t("import") }}</button>
            <button class="xbtn" @click="call('uiReload')" :title="t('reload')">↻</button>
            <button class="xbtn" @click="close" :title="t('close')">✕</button>
          </header>

          <div class="filters">
            <div class="fgroup">
              <span class="flabel">{{ t("radius") }}</span>
              <button v-for="r in radii" :key="r" class="chip" :class="{ on: radiusKm === r }" @click="call('uiSetSetting', 'radiusKm', r)">{{ r }} km</button>
              <button class="chip" :class="{ on: f.near === '1' }" @click="setF('near', f.near === '1' ? '' : '1')">📍 {{ t("onlyNear") }}</button>
            </div>
            <div class="fgroup">
              <span class="flabel">{{ t("country") }}</span>
              <button class="chip" :class="{ on: !f.country }" @click="setF('country', '')">{{ t("all") }}</button>
              <button v-for="c in facets.country" :key="c" class="chip" :class="{ on: f.country === c }" @click="setF('country', c)">
                <img :src="flag(c)" class="flag" alt="" />{{ c.toUpperCase() }}
              </button>
            </div>
            <div class="fgroup">
              <span class="flabel">{{ t("type") }}</span>
              <button class="chip" :class="{ on: !f.type }" @click="setF('type', '')">{{ t("all") }}</button>
              <button v-for="c in facets.type" :key="c" class="chip" :class="{ on: f.type === c }" @click="setF('type', c)">{{ t(c) }}</button>
            </div>
            <div class="fgroup" v-if="facets.category.length">
              <span class="flabel">{{ t("category") }}</span>
              <button class="chip" :class="{ on: !f.category }" @click="setF('category', '')">{{ t("all") }}</button>
              <button v-for="c in facets.category" :key="c" class="chip" :class="{ on: f.category === c }" @click="setF('category', c)">{{ c }}</button>
            </div>
            <div class="fgroup">
              <span class="flabel">{{ t("surface") }}</span>
              <button class="chip" :class="{ on: !f.surface }" @click="setF('surface', '')">{{ t("all") }}</button>
              <button v-for="c in facets.surface" :key="c" class="chip" :class="{ on: f.surface === c }" @click="setF('surface', c)">{{ t(c) }}</button>
            </div>
            <div class="fgroup">
              <span class="flabel">{{ t("status") }}</span>
              <button class="chip" :class="{ on: !f.status }" @click="setF('status', '')">{{ t("all") }}</button>
              <button v-for="c in facets.status" :key="c" class="chip" :class="{ on: f.status === c }" @click="setF('status', c)">{{ t(c) }}</button>
            </div>
          </div>

          <div class="scroll">
            <div v-if="s && !s.earth" class="notice">{{ s.reason }}</div>
            <template v-for="g in groups" :key="g.key">
              <h2 class="sect"><span class="slash small"></span>{{ t(g.key) }}<span v-if="g.key === 'near'" class="dim small sectx">&nbsp;· {{ radiusKm }} km</span></h2>
              <div class="grid">
                <button v-for="e in g.items" :key="e.id" class="card" :class="{ on: focus && focus.id === e.id }"
                        @click="focusId = e.id" @dblclick="open(e.id)">
                  <div class="thumb">
                    <img v-if="e.logo" :src="e.logo" class="logo" alt="" />
                    <div v-else class="nologo">{{ e.short || e.name }}</div>
                    <span v-if="e.status === 'live'" class="badge live">{{ t("live") }}</span>
                    <span v-if="s.proposalId === e.id" class="badge here">{{ t("here") }}</span>
                  </div>
                  <div class="cap">
                    <img v-if="e.country" :src="flag(e.country)" class="flag" alt="" />
                    <span class="cname">{{ e.short || e.name }}</span>
                    <span v-if="e.boxM != null && e.near" class="cyear">{{ e.boxM > 0 ? dist(e.boxM) : '📍' }}</span>
                    <span v-else class="cyear">{{ e.custom ? t("custom") : (e.dates || '').slice(0, 4) }}</span>
                  </div>
                </button>
              </div>
            </template>
            <div v-if="s && !events.length" class="empty"><b>{{ t("none") }}</b><div class="dim">{{ t("noneHint") }}</div></div>
            <div v-if="s" class="dim small foot">{{ t("noneHint2", { dir: s.importDir, packs: list(s.packDirs).join(' · ') }) }}</div>
          </div>
        </section>

        <!-- panel derecho de detalle -->
        <aside class="side panel" v-if="focus">
          <h3 class="side-title">{{ focus.name }}</h3>
          <div class="side-img">
            <img v-if="focus.logo" :src="focus.logo" alt="" />
            <div v-else class="nologo big">{{ focus.short || focus.name }}</div>
          </div>
          <div class="tags">
            <span class="tagx"><img v-if="focus.country" :src="flag(focus.country)" class="flag" alt="" />{{ focus.city || focus.country }}</span>
            <span class="tagx">{{ t(focus.type) }}</span>
            <span class="tagx" v-for="c in list(focus.categories)" :key="c">{{ c }}</span>
            <span class="tagx" v-if="focus.source && !focus.custom">{{ t("official") }}</span>
          </div>
          <p class="desc">{{ focus.description }}</p>
          <ul class="info">
            <li><span class="ico">ⓘ</span><div><small>{{ t("challenge") }}:</small><b>{{ t(focus.type) }} · {{ t(focus.surface) }}</b></div></li>
            <li v-if="focus.championship"><span class="ico">🏆</span><div><small>{{ t("championship") }}:</small><b>{{ focus.championship }}</b></div></li>
            <li v-if="focus.organizer"><span class="ico">👤</span><div><small>{{ t("organizer") }}:</small><b>{{ focus.organizer }}</b></div></li>
            <li><span class="ico">📅</span><div><small>{{ t("dates") }}:</small><b>{{ dates(focus.dates) }}</b></div></li>
            <li><span class="ico">⛰</span><div><small>{{ t("place") }}:</small><b>{{ [focus.city, focus.region].filter(Boolean).join(', ') }}</b></div></li>
            <li><span class="ico">🏁</span><div><small>{{ t("stagesInfo") }}:</small><b>{{ focus.stageCount }} · {{ km(focus.stageKm) }}</b></div></li>
            <li v-if="focus.boxM != null"><span class="ico">📍</span><div><b>{{ focus.boxM > 0 ? t("away", { d: dist(focus.boxM) }) : t("here") }}</b></div></li>
          </ul>
          <button class="go-btn" @click="open(focus.id)">▶ {{ t("openRally") }}</button>
        </aside>
      </div>
    </template>

    <!-- ===================== ficha del rally (como la del modo rally del juego) ===================== -->
    <template v-else>
      <div class="rally">
        <div class="rcol panel">
          <header class="rhead">
            <span class="slash big"></span>
            <div class="rtitle">
              <h1>{{ sel.name }}</h1>
              <div class="rsub"><img v-if="sel.country" :src="flag(sel.country)" class="flag" alt="" />{{ [sel.city, dates(sel.dates), sel.championship].filter(Boolean).join(' · ') }}</div>
            </div>
            <img v-if="sel.logo" :src="sel.logo" class="rlogo" alt="" />
          </header>
          <nav class="tabs">
            <button class="navarrow" @click="back">‹</button>
            <button class="tab" :class="{ on: tab === 'info' }" @click="tab = 'info'" :title="t('summary')">ⓘ</button>
            <button class="tab" :class="{ on: tab === 'ratings' }" @click="tab = 'ratings'" :title="t('ratings')">▮▮▮</button>
            <div class="grow"></div>
            <button class="xbtn" @click="close" :title="t('close')">✕</button>
          </nav>

          <div class="rbody" v-if="tab === 'info'">
            <div class="col">
              <h2 class="sect"><span class="slash small"></span>{{ t("summary") }}</h2>
              <p class="desc">{{ sel.description }}</p>
              <ul class="bul">
                <li>{{ t("stageDist", { d: km(sel.stageKm) }) }}</li>
                <li>{{ t("liaisonDist", { d: km(sel.liaisonKm) }) }}</li>
                <li v-if="sel.totalKm">{{ t("totalDist", { d: km(sel.totalKm) }) }}</li>
                <li v-if="sel.rallyKm">{{ t("rallyDist", { d: km(sel.rallyKm), s: km(sel.rallyStageKm), l: km(sel.rallyLiaisonKm) }) }}</li>
              </ul>
              <ul class="bul stages-bul">
                <li v-for="st in stages" :key="st.id"><b>{{ plate(st) }} {{ st.title }}</b> — {{ km(st.km) }} · {{ t(st.surface) }} 100%</li>
              </ul>
              <h2 class="sect"><span class="slash small"></span>{{ t("rules") }}</h2>
              <ul class="bul">
                <li v-for="k in (mode === 'rally' ? ['ruleR1','ruleR2','ruleR3','ruleR4','rule2','rule3','rule4','rule5'] : ['rule1','rule2','rule3','rule4','rule5','rule6'])" :key="k">{{ t(k) }}</li>
              </ul>
              <p class="dim small">{{ t("source") }}: {{ sel.source }}
                <a v-if="sel.link" class="ilink" @click="call('uiOpenLink', sel.link)">{{ sel.link }}</a></p>
            </div>
            <div class="col">
              <h2 class="sect"><span class="slash small"></span>{{ t("settings") }}</h2>
              <div class="set-label">{{ t("copilot") }}</div>
              <div class="selector">
                <button @click="cycleVoice(-1)">‹</button>
                <div class="sel-val"><b>{{ voice.name }} - {{ voice.style }}</b><small>{{ voice.dialect }}</small>
                  <div class="dots"><span v-for="v in voices" :key="v.id" :class="{ on: v.id === voice.id }"></span></div>
                </div>
                <button @click="cycleVoice(1)">›</button>
              </div>
              <div class="set-label">{{ t("liaisonKmh") }}</div>
              <div class="chips-row">
                <button v-for="v in [40, 50, 60, 80, 100]" :key="v" class="chip" :class="{ on: set.liaisonKmh === v }" @click="call('uiSetSetting', 'liaisonKmh', v)">{{ v }} km/h</button>
              </div>
              <div class="set-label">{{ t("notesLead") }}</div>
              <div class="chips-row">
                <button v-for="o in [[6, 'early'], [4.5, 'normal'], [3, 'late']]" :key="o[0]" class="chip" :class="{ on: set.notesLeadS === o[0] }" @click="call('uiSetSetting', 'notesLeadS', o[0])">{{ t(o[1]) }}</button>
              </div>
              <div class="set-label">{{ t("notesSize") }}</div>
              <div class="chips-row">
                <button v-for="v in [0.55, 0.72, 0.9, 1.1]" :key="v" class="chip" :class="{ on: set.notesScale === v }" @click="call('uiSetSetting', 'notesScale', v)">{{ Math.round(v * 100) }} %</button>
              </div>
              <div class="set-label">{{ t("notesAlpha") }}</div>
              <div class="chips-row">
                <button v-for="v in [0.5, 0.72, 0.9, 1]" :key="v" class="chip" :class="{ on: set.notesOpacity === v }" @click="call('uiSetSetting', 'notesOpacity', v)">{{ Math.round(v * 100) }} %</button>
              </div>
              <div v-for="k in toggles" :key="k" class="toggle-row" @click="toggle(k)">
                <span>{{ t(k) }}</span>
                <span class="toggle" :class="{ on: set[k] }"><span class="knob"></span></span>
              </div>
              <div v-if="s && s.racingLineMod" class="toggle-row" @click="toggle('racingLine')">
                <span>{{ t("racingLine") }}</span>
                <span class="toggle" :class="{ on: set.racingLine }"><span class="knob"></span></span>
              </div>
              <div class="set-label">{{ t("recMods") }}</div>
              <p class="recmod dim">{{ t("recModsHelp") }}</p>
              <p v-for="r in (s && s.recMods) || []" :key="r.id" class="recmod">
                <b>{{ r.name }}</b> — {{ t("rec_" + r.id) }}
                <span :class="r.active ? 'ok' : 'warn'">· {{ r.active ? t("recActive") : r.installed ? t("recInactive") : t("recMissing") }}</span>
                <a v-if="!r.installed" href="#" @click.prevent="call('uiOpenLink', r.url)">{{ t("recDownload") }}</a>
              </p>
              <div class="toggle-row" @click="toggle('recModsAuto')">
                <span>{{ t("recModsAuto") }}</span>
                <span class="toggle" :class="{ on: set.recModsAuto !== false }"><span class="knob"></span></span>
              </div>
            </div>
          </div>

          <div class="rbody one" v-else>
            <div class="col wide">
              <h2 class="sect"><span class="slash small"></span>{{ t("ratings") }}</h2>
              <table class="rtable">
                <thead><tr><th></th><th>{{ t("tries") }}</th><th>{{ t("best") }}</th><th>{{ t("last") }}</th></tr></thead>
                <tbody>
                  <tr v-if="sel.rallyRuns">
                    <td><b>{{ t("rallyBest") }}</b></td><td class="mono">{{ sel.rallyRuns }}</td>
                    <td class="mono gold">{{ clock(sel.rallyBest) }}</td><td></td>
                  </tr>
                  <tr v-for="st in stages" :key="st.id">
                    <td><b>{{ plate(st) }}</b> {{ st.title }}</td>
                    <td class="mono">{{ st.tries || 0 }}</td>
                    <td class="mono gold">{{ clock(st.best) }}</td>
                    <td class="mono small">{{ list(st.attempts).slice(0, 3).map(a => clock(a.total) + (a.penalty ? ' (+' + a.penalty + 's)' : '')).join('  ·  ') || '—' }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
          <!-- con un tramo en marcha, en el sitio de Iniciar está Cancelar (no se puede iniciar otro a la vez) -->
          <button v-if="mode === 'stage' && anyActive" class="go-btn bottom danger" @click="call('uiCancelStage')">{{ t("cancel") }}<template v-if="!isRunning(pick)"> · {{ activeLabel }}</template></button>
          <button v-else-if="mode === 'stage'" class="go-btn bottom" :disabled="!pick || !s.pos" @click="startPick">{{ t("start") }}</button>
          <button v-else class="go-btn bottom" :disabled="!s.pos || !itinerary.length || rallyHere || anyActive" @click="startRally">{{ rallyHere ? t("rallyRunning", { l: s.rallyActive.label || '' }) : t("startRally") }}</button>
        </div>

        <!-- tramos del rally -->
        <div class="scol panel">
          <div class="modes">
            <button :class="{ on: mode === 'stage' }" @click="mode = 'stage'">{{ t("modeStage") }}</button>
            <button :class="{ on: mode === 'rally' }" :disabled="!itinerary.length" @click="mode = 'rally'">{{ t("modeRally") }}</button>
          </div>
          <template v-if="mode === 'rally'">
            <h2 class="sect"><span class="slash small"></span>{{ t("itinerary") }}</h2>
            <div class="smeta">{{ t("startFrom") }}: <b>{{ fromRun ? 'SS' + fromRun : t("fromStart") }}</b></div>
            <div class="slist">
              <button v-for="it in itinerary" :key="it.label" class="stage itin" :class="{ on: fromRun ? it.run === fromRun : it === itinerary[0], dimmed: fromRun && it.run && it.run < fromRun }"
                      :disabled="it.final" @click="fromRun = (it.run && it.run !== firstRun) ? it.run : null">
                <span class="plate tc">{{ it.label }}</span>
                <div class="sinfo">
                  <div class="sname">{{ it.final ? t("service") || it.title : it.title }}<span v-if="it.run" class="plate">SS{{ it.run }}</span></div>
                  <div class="smeta">{{ t("liaison") }} {{ km(it.liaisonKm) }} · {{ it.minutes }} min<template v-if="!it.real"> · {{ t("gpsOnly") }}</template></div>
                </div>
              </button>
            </div>
            <div class="sactions" v-if="rallyHere">
              <button class="btn" @click="call('uiSkipLiaison')">{{ t("skipLiaison") }}</button>
              <button class="btn danger" @click="call('uiCancelStage')">{{ t("abandon") }}</button>
            </div>
          </template>
          <template v-else>
          <h2 class="sect"><span class="slash small"></span>{{ t("pickStage") }}</h2>
          <div class="slist">
            <button v-for="st in stages" :key="st.id" class="stage" :class="{ on: pick && pick.id === st.id, run: isRunning(st) }" @click="pickId = st.id">
              <div class="sart"><RouteArt :outline="st.outline" :tone="st.kind === 'ss' ? 'red' : 'blue'" /></div>
              <div class="sinfo">
                <div class="sname"><span class="plate">{{ plate(st) }}</span>{{ st.title }}</div>
                <div class="smeta">{{ km(st.km) }} · {{ t(st.surface) }}<template v-if="st.road"> · {{ st.road }}</template></div>
                <div class="smeta" v-if="st.distM != null">{{ t("startIn", { d: dist(st.distM) }) }}</div>
                <div class="smeta gold" v-if="st.best">{{ t("best") }}: {{ clock(st.best) }}</div>
              </div>
            </button>
          </div>
          <div class="modes" v-if="pick && pick.hasReverse && !anyActive">
            <button :class="{ on: !reverse }" @click="reverse = false">→ {{ t("dirNormal") }}</button>
            <button :class="{ on: reverse }" @click="reverse = true">← {{ t("dirReverse") }}</button>
          </div>
          <div class="sactions" v-if="pick && !anyActive">
            <button class="btn" :disabled="!s.pos" @click="call('uiGo', sel.id, pick.id, 'gps', reverse)">{{ t("gps") }}</button>
          </div>
          </template>
        </div>
      </div>
    </template>

    <!-- ===================== importar una ruta (KMZ, KML, GPX, GeoJSON, OSM) ===================== -->
    <div v-if="s && s.importOpen" class="impov" @keydown.esc.stop="call('uiImportOpen', false)">
      <section class="panel impbox">
        <header class="ttl">
          <span class="slash"></span>
          <h1>{{ t("importTitle") }}</h1>
          <div class="grow"></div>
          <button class="xbtn" @click="call('uiImportFolder')">📁 {{ t("openFolder") }}</button>
          <button class="xbtn" @click="call('uiImportRun', '')">↻ {{ t("importAll") }}</button>
          <button class="xbtn" @click="call('uiImportOpen', false)">✕</button>
        </header>
        <div class="imphelp dim small">
          <p>{{ t("importHelp1", { dir: s.importDir }) }}</p>
          <p>{{ t("importHelp2") }}</p>
        </div>
        <div class="newimp">
          <div class="set-label">{{ t("newEvent") }}</div>
          <div class="frow"><label>{{ t("m_name") }}</label>
            <input v-model="up.name" type="text" :placeholder="t('ph_name')" @keydown.stop @focus="typing(true)" @blur="typing(false)" /></div>
          <div class="frow"><label>{{ t("upRoute") }}</label>
            <input type="file" multiple accept=".kmz,.kml,.gpx,.geojson,.osm" @change="e => (up.routes = Array.from(e.target.files || []))" /></div>
          <div class="frow"><label>{{ t("upLogo") }}</label>
            <input type="file" accept=".png,.jpg,.jpeg,.webp" @change="e => (up.logo = (e.target.files || [])[0] || null)" /></div>
          <div class="frow"><label>{{ t("surface") }}</label>
            <select v-model="up.surface"><option value="">{{ t("surfAuto") }}</option><option v-for="o in ['asphalt', 'gravel', 'snow', 'mixed']" :key="o" :value="o">{{ t(o) }}</option></select></div>
          <div class="frow"><label>{{ t("m_description") }}</label>
            <textarea v-model="up.description" rows="2" @keydown.stop @focus="typing(true)" @blur="typing(false)"></textarea></div>
          <div class="frow"><label>{{ t("m_link") }}</label>
            <input v-model="up.link" type="text" :placeholder="t('ph_link')" @keydown.stop @focus="typing(true)" @blur="typing(false)" /></div>
          <div class="frow btns">
            <button class="btn" :disabled="up.busy || !up.name || !up.routes.length" @click="startUpload">⤓ {{ t("upGo") }}</button>
            <span class="dim small">{{ up.msg }}</span>
          </div>
        </div>
        <div v-if="!imports.length" class="empty"><b>{{ t("importNone") }}</b></div>
        <div class="implist">
          <div v-for="i in imports" :key="i.key" class="impitem" :class="{ on: impKey === i.key }">
            <div class="imphead" @click="pickImport(i)">
              <img v-if="i.logo" :src="i.logo" class="implogo" alt="" />
              <div v-else class="implogo nologo">{{ (i.name || i.key).slice(0, 18) }}</div>
              <div class="grow">
                <b>{{ i.name || i.key }}</b>
                <div class="dim small">{{ list(i.files).join(" · ") }}<template v-if="!i.hasLogo"> · {{ t("noLogo") }}</template></div>
                <div class="small" v-if="i.status !== 'error'">{{ i.stageCount }} {{ t("stagesShort") }} · {{ km(i.stageKm) }} · {{ t("liaison") }} {{ km(i.liaisonKm) }}</div>
                <div class="small red" v-else>{{ i.error }}</div>
              </div>
              <span class="tagx" :class="i.status">{{ t("imp_" + i.status) }}</span>
            </div>
            <div v-if="impKey === i.key" class="impform">
              <div class="frow" v-for="k in metaKeys" :key="k">
                <label>{{ t("m_" + k) }}</label>
                <select v-if="k === 'type'" v-model="form[k]"><option v-for="o in ['rally', 'raid', 'hillclimb', 'custom']" :key="o" :value="o">{{ t(o) }}</option></select>
                <select v-else-if="k === 'surface'" v-model="form[k]"><option v-for="o in ['asphalt', 'gravel', 'snow', 'mixed']" :key="o" :value="o">{{ t(o) }}</option></select>
                <textarea v-else-if="k === 'description'" v-model="form[k]" rows="3" @keydown.stop @focus="typing(true)" @blur="typing(false)"></textarea>
                <input v-else v-model="form[k]" type="text" :placeholder="t('ph_' + k)" @keydown.stop @focus="typing(true)" @blur="typing(false)" />
              </div>
              <div class="dim small" v-if="list(i.warnings).length">⚠ {{ list(i.warnings).join(" · ") }}</div>
              <div class="dim small">{{ t("autoFilled") }}</div>
              <div class="impstages small">
                <span v-for="st in list(i.stages)" :key="st.id">{{ st.id.toUpperCase() }} {{ st.title }} ({{ km(st.km) }})</span>
              </div>
              <div class="frow btns">
                <button class="btn" @click="saveMeta(i)">{{ t("saveImport") }}</button>
                <button class="btn ghost" @click="call('uiImportRun', i.key)">↻ {{ t("reimport") }}</button>
                <button v-if="i.status !== 'error'" class="btn ghost" @click="openImported(i)">{{ t("seeEvent") }} ›</button>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue"
import { useEvents } from "@/services/events"
import RouteArt from "./RouteArt.vue"
import { state, call, onState, typing, list, t, dist, km, clock, flag, dates } from "./store.js"

const events_ = useEvents()
events_.on("EarthRaidState", m => onState(m))

const rootEl = ref(null)
const s = state
const q = ref("")
const focusId = ref(null)
const pickId = ref(null)
const tab = ref("info")
const mode = ref("stage")
const reverse = ref(false)
const fromRun = ref(null)
const radii = [10, 25, 50, 100, 250, 1000]
let timer = null

onMounted(() => { if (rootEl.value) rootEl.value.focus(); call("uiState") })
onBeforeUnmount(() => { typing(false); if (timer) clearTimeout(timer) })

const events = computed(() => list(s.value && s.value.events))
const f = computed(() => (s.value && s.value.filters) || {})
const facets = computed(() => {
  const x = (s.value && s.value.facets) || {}
  return { country: list(x.country), type: list(x.type), category: list(x.category), surface: list(x.surface), status: list(x.status) }
})
const radiusKm = computed(() => (s.value && s.value.settings && s.value.settings.radiusKm) || 50)
const filtered = computed(() => !!(f.value.country || f.value.type || f.value.category || f.value.surface || f.value.status || f.value.near || (s.value && s.value.q)))
const groups = computed(() => {
  const g = [
    { key: "near", items: events.value.filter(e => e.near) },
    { key: "live", items: events.value.filter(e => !e.near && e.status === "live") },
    { key: "upcoming", items: events.value.filter(e => !e.near && e.status === "upcoming") },
    { key: "past", items: events.value.filter(e => !e.near && e.status === "past") },
  ]
  return g.filter(x => x.items.length)
})
const focus = computed(() => events.value.find(e => e.id === focusId.value) || events.value[0] || null)
const sel = computed(() => (s.value && s.value.sel) || null)
const stages = computed(() => list(sel.value && sel.value.stages))
const pick = computed(() => stages.value.find(x => x.id === pickId.value) || stages.value.find(x => x.kind === "ss") || null)
watch(() => sel.value && sel.value.id, () => { pickId.value = null; fromRun.value = null })
const itinerary = computed(() => list(sel.value && sel.value.itinerary))
const firstRun = computed(() => (itinerary.value[0] && itinerary.value[0].run) || null)
const rallyHere = computed(() => !!(s.value && s.value.rallyActive && sel.value && s.value.rallyActive.eventId === sel.value.id))
watch(rallyHere, v => { if (v) mode.value = "rally" }, { immediate: true })
function startRally() { if (sel.value) call("uiStartRally", sel.value.id, fromRun.value || "nil") }

const set = computed(() => (s.value && s.value.settings) || {})
const voices = computed(() => list(s.value && s.value.voicepacks))
const voice = computed(() => voices.value.find(v => v.id === set.value.voicepack) || voices.value[0] || { name: "—" })
const toggles = ["raceHud", "visualNotes", "voice", "notesSafe", "falseStart", "recoveryPenalty", "noTraffic", "closures", "arrows", "cautions", "ambience", "sounds"]

function typed() { if (timer) clearTimeout(timer); timer = setTimeout(() => call("uiSearch", q.value), 200) }
function clearQ() { q.value = ""; call("uiSearch", "") }
function setF(k, v) { call("uiFilter", k, v) }
function open(id) { tab.value = "info"; call("uiSelect", id) }
function back() { call("uiBack") }
// ---- importar
const imports = computed(() => list(s.value && s.value.imports))
const metaKeys = ["name", "short", "dates", "country", "city", "region", "championship", "organizer", "type", "surface", "link", "source", "description"]
const impKey = ref(null)
const form = ref({})

// ---- subir un evento: los archivos se leen aquí y van a Lua en trozos (Lua valida y escribe en la carpeta de import)
const CHUNK = 48000
const up = ref({ name: "", routes: [], logo: null, description: "", link: "", surface: "", busy: false, msg: "", key: null })
let upResolve = null
events_.on("EarthRaidUpload", d => {
  if (!d) return
  if (d.phase === "error") { up.value.busy = false; up.value.msg = "⚠ " + (d.file ? d.file + ": " : "") + d.error }
  if (upResolve) { const r = upResolve; upResolve = null; r(d) }
})
function waitUpload(ms = 20000) {
  return new Promise((res, rej) => { upResolve = res; setTimeout(() => { if (upResolve === res) { upResolve = null; rej(new Error("timeout")) } }, ms) })
}
function readB64(file) {
  return new Promise((res, rej) => {
    const r = new FileReader()
    r.onload = () => res(String(r.result).replace(/^data:[^,]*,/, ""))
    r.onerror = () => rej(r.error)
    r.readAsDataURL(file)
  })
}
async function sendFile(key, file) {
  const b64 = await readB64(file)
  const n = Math.max(1, Math.ceil(b64.length / CHUNK))
  const done = waitUpload(60000)
  for (let i = 0; i < n; i++) {
    call("uiUpload", key, file.name, i + 1, n, b64.slice(i * CHUNK, (i + 1) * CHUNK))
    up.value.msg = file.name + " " + Math.round(((i + 1) / n) * 100) + " %"
    if (i % 4 === 3) await new Promise(r => setTimeout(r, 0))
  }
  return done
}
async function startUpload() {
  const u = up.value
  if (u.busy || !u.name || !u.routes.length) return
  u.busy = true; u.msg = t("upSending"); typing(false)
  try {
    const k = waitUpload()
    call("uiUploadNew", u.name)
    const first = await k
    if (!first || first.phase !== "key") return
    const key = first.key
    for (const f of [...u.routes, ...(u.logo ? [u.logo] : [])]) {
      const r = await sendFile(key, f)
      if (!u.busy || (r && r.phase === "error")) return
    }
    const fin = waitUpload(60000)
    call("uiUploadFinish", key, JSON.stringify({ name: u.name, description: u.description, link: u.link, surface: u.surface }))
    const end = await fin
    if (end && end.phase === "error") return
    u.msg = "✓ " + t("upDone"); impKey.value = key
    Object.assign(u, { name: "", routes: [], logo: null, description: "", link: "", surface: "" })
  } catch (e) {
    u.msg = "⚠ " + (e && e.message ? e.message : e)
  } finally { u.busy = false }
}
function pickImport(i) {
  impKey.value = impKey.value === i.key ? null : i.key
  const m = Object.assign({}, i.meta || {})
  if (!m.name) m.name = i.name || ""
  if (!m.type) m.type = "rally"
  if (!m.surface) m.surface = "asphalt"
  form.value = m
}
function saveMeta(i) { typing(false); call("uiImportMeta", i.key, JSON.stringify(form.value)) }
function openImported(i) { call("uiImportOpen", false); open(i.id) }
function close() { call("uiClose") }
function escape() { if (s.value && s.value.importOpen) call("uiImportOpen", false); else if (sel.value) back(); else close() }
function toggle(k) { call("uiSetSetting", k, !set.value[k]) }
function cycleVoice(dir) {
  const vs = voices.value
  if (!vs.length) return
  const i = Math.max(0, vs.findIndex(v => v.id === voice.value.id))
  call("uiSetSetting", "voicepack", vs[(i + dir + vs.length) % vs.length].id)
}
function plate(st) {
  const r = list(st.runs)
  return r.length ? "SS" + r.join("/") : "SD"
}
function isRunning(st) {
  const a = s.value && s.value.stageActive
  return !!(st && a && sel.value && a.eventId === sel.value.id && (a.stageId === st.id || a.stageId === st.id + "R"))
}
// un tramo en marcha (de este evento o de otro): se preselecciona y no se puede iniciar otro
const anyActive = computed(() => !!(s.value && s.value.stageActive))
const activeLabel = computed(() => (s.value && s.value.stageActive && s.value.stageActive.title) || "")
function selectActive() {
  const a = s.value && s.value.stageActive
  if (!a) return
  if (!sel.value || sel.value.id !== a.eventId) { call("uiSelect", a.eventId); return }
  const base = String(a.stageId).replace(/R$/, "")
  if (stages.value.some(x => x.id === base)) {
    mode.value = "stage"
    pickId.value = base
    reverse.value = String(a.stageId).endsWith("R") && base !== a.stageId
  }
}
watch(() => [s.value && s.value.stageActive && s.value.stageActive.stageId, sel.value && sel.value.id], selectActive, { immediate: true })
// sin tramo al revés en el rally, siempre en su sentido
watch(() => pick.value && pick.value.id, () => { if (pick.value && !pick.value.hasReverse && !isRunning(pick.value)) reverse.value = false })
// Iniciar: si estás lejos, el tramo se carga y el coche aparece 100 m antes del control horario (pantalla de carga)
function startPick() { if (pick.value && !anyActive.value) call("uiPlay", sel.value.id, pick.value.id, reverse.value) }
</script>

<style scoped lang="scss">
.impov { position: fixed; inset: 0; z-index: 60; background: rgba(0, 0, 0, 0.55); display: flex; align-items: center; justify-content: center; }
.impbox { width: min(1100px, 92vw); max-height: 88vh; display: flex; flex-direction: column; padding: 0 0 14px; }
.impbox .ttl { display: flex; align-items: center; padding: 14px 18px; gap: 8px; }
.imphelp { padding: 0 20px; } .imphelp p { margin: 4px 0; }
.implist { overflow: auto; padding: 6px 18px; display: flex; flex-direction: column; gap: 8px; }
.impitem { background: rgba(40, 42, 48, 0.85); border-radius: 6px; border: 1px solid rgba(255, 255, 255, 0.08); }
.impitem.on { border-color: var(--bng-orange, #ff6600); }
.imphead { display: flex; gap: 14px; align-items: center; padding: 10px 12px; cursor: pointer; }
.implogo { width: 140px; height: 70px; object-fit: contain; background: rgba(255, 255, 255, 0.06); border-radius: 4px; display: flex; align-items: center; justify-content: center; font-size: 13px; text-align: center; }
.impform { padding: 4px 14px 12px; display: flex; flex-direction: column; gap: 6px; }
.frow { display: flex; gap: 10px; align-items: center; }
.frow label { width: 150px; color: #a7abb3; font-size: 13px; }
.frow input, .frow select, .frow textarea { flex: 1; background: rgba(0, 0, 0, 0.35); color: #f2f2f2; border: 1px solid rgba(255, 255, 255, 0.15); border-radius: 4px; padding: 5px 8px; font-size: 14px; }
.frow.btns { justify-content: flex-end; margin-top: 6px; }
.impstages { display: flex; flex-wrap: wrap; gap: 4px 12px; color: #c9ccd2; }
.tagx.new { background: #2e7d32; } .tagx.ok { background: #455a64; } .tagx.error { background: #b71c1c; }
.red { color: #ff6b6b; }
.ilink { color: #4fc3f7; cursor: pointer; margin-left: 6px; text-decoration: underline; }
.xbtn.imp { width: auto; padding: 0 12px; }
// Colores y formas del menú del juego: paneles oscuros translúcidos, títulos en cursiva con la barra naranja, botón
// principal naranja
.er {
  --or: var(--bng-orange, #ff6600);
  --panel: rgba(18, 19, 22, 0.88);
  --panel2: rgba(40, 42, 48, 0.85);
  --ink: #f2f2f2;
  --dim: #a7abb3;
  --hair: rgba(255, 255, 255, 0.1);
  position: fixed; inset: 0; z-index: 50; color: var(--ink); outline: none; pointer-events: auto;
  background: rgba(0, 0, 0, 0.35); font-size: 15px;
}
.panel { background: var(--panel); border-radius: 6px; box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5); }
.dim { color: var(--dim); }
.small { font-size: 12.5px; }
.grow { flex: 1; }
.mono { font-variant-numeric: tabular-nums; }
.gold { color: #f5c400; }
.flag { width: 22px; height: 15px; object-fit: cover; border-radius: 2px; margin-right: 6px; vertical-align: -2px; box-shadow: 0 0 0 1px rgba(0,0,0,.4); }
.slash { display: inline-block; width: 16px; height: 34px; background: var(--or); transform: skewX(-18deg); margin-right: 14px; flex: none; }
.slash.small { width: 8px; height: 20px; margin-right: 10px; }
.slash.big { width: 30px; height: 96px; }
h1 { margin: 0; font-size: 34px; font-style: italic; font-weight: 800; }
.sect { display: flex; align-items: center; margin: 14px 0 10px; font-size: 22px; font-style: italic; font-weight: 800; }
.xbtn { background: none; border: 0; color: var(--ink); font-size: 22px; cursor: pointer; padding: 4px 10px; }
.xbtn:hover { color: var(--or); }

// ---- catálogo
.browser { position: absolute; inset: 1.2vh 1vw; display: grid; grid-template-columns: 1fr 490px; gap: 14px; }
.main { display: flex; flex-direction: column; min-height: 0; }
.ttl { display: flex; align-items: center; padding: 10px 14px; border-bottom: 1px solid var(--hair); }
.find input { width: 340px; padding: 8px 12px; border-radius: 4px; border: 1px solid var(--hair); background: rgba(0,0,0,.4); color: var(--ink); font: inherit; }
.find input:focus { outline: 2px solid var(--or); }
.filters { display: flex; flex-wrap: wrap; gap: 6px 22px; padding: 10px 16px; border-bottom: 1px solid var(--hair); }
.fgroup { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
.flabel { color: var(--dim); font-size: 12px; text-transform: uppercase; letter-spacing: .1em; margin-right: 4px; }
.chip { display: inline-flex; align-items: center; padding: 4px 10px; border-radius: 3px; border: 1px solid var(--hair); background: var(--panel2);
  color: var(--ink); font: inherit; font-size: 13px; cursor: pointer; }
.chip.on { background: var(--or); border-color: var(--or); color: #fff; }
.scroll { flex: 1; overflow-y: auto; padding: 4px 16px 16px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 10px; }
.card { padding: 0; border: 2px solid transparent; background: #15161a; color: var(--ink); text-align: left; cursor: pointer; border-radius: 3px; overflow: hidden; font: inherit; }
.card:hover, .card.on { border-color: var(--or); }
.thumb { position: relative; height: 140px; background: radial-gradient(circle at 50% 40%, #3a3d45, #16171b); display: flex; align-items: center; justify-content: center; }
.thumb .logo { max-width: 92%; max-height: 88%; object-fit: contain; }
.nologo { font-size: 22px; font-style: italic; font-weight: 800; padding: 10px; text-align: center; }
.nologo.big { font-size: 30px; height: 200px; display: flex; align-items: center; justify-content: center; }
.badge { position: absolute; top: 8px; left: 8px; font-size: 11px; font-weight: 800; text-transform: uppercase; padding: 2px 7px; border-radius: 2px; }
.badge.live { background: #e0393e; }
.badge.here { left: auto; right: 8px; background: #17c936; color: #062b0d; }
.cap { display: flex; align-items: center; padding: 8px 10px; background: #1f2126; }
.cname { flex: 1; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.cyear { color: var(--dim); font-size: 13px; }
.empty, .notice { padding: 24px 6px; }
.side { display: flex; flex-direction: column; padding: 14px 16px; overflow-y: auto; }
.side-title { margin: 0 0 10px; font-size: 26px; font-style: italic; font-weight: 800; }
.side-img { background: radial-gradient(circle at 50% 40%, #3a3d45, #121316); border-radius: 3px; padding: 14px; display: flex; justify-content: center; }
.side-img img { max-width: 100%; max-height: 220px; object-fit: contain; }
.tags { display: flex; flex-wrap: wrap; gap: 6px; margin: 10px 0; }
.tagx { display: inline-flex; align-items: center; padding: 3px 10px; background: var(--panel2); border-radius: 3px; font-size: 14px; }
.desc { line-height: 1.45; color: #dcdfe4; }
.info { list-style: none; padding: 0; margin: 8px 0 14px; display: grid; gap: 10px; }
.info li { display: flex; gap: 12px; align-items: flex-start; }
.info .ico { width: 26px; text-align: center; font-size: 18px; }
.info small { display: block; color: var(--dim); }
.go-btn { margin-top: auto; width: 100%; padding: 14px; border: 0; border-radius: 3px; background: var(--or); color: #fff;
  font: inherit; font-size: 22px; font-weight: 800; font-style: italic; cursor: pointer; }
.go-btn:hover { filter: brightness(1.1); }
.go-btn:disabled { opacity: .45; cursor: default; }

// ---- ficha del rally
.rally { position: absolute; inset: 1.2vh 1vw; display: grid; grid-template-columns: minmax(780px, 1.35fr) minmax(420px, 1fr); gap: 14px; }
.rcol { display: flex; flex-direction: column; min-height: 0; padding-bottom: 12px; }
.rhead { display: flex; align-items: center; padding: 12px 16px 6px; }
.rtitle { flex: 1; }
.rtitle h1 { font-size: 44px; line-height: 1.05; }
.rsub { color: var(--dim); margin-top: 4px; display: flex; align-items: center; }
.rlogo { height: 92px; max-width: 220px; object-fit: contain; }
.tabs { display: flex; align-items: center; gap: 6px; padding: 4px 16px 8px; border-bottom: 1px solid var(--hair); }
.navarrow { background: var(--panel2); border: 0; color: var(--ink); font-size: 24px; width: 40px; height: 40px; border-radius: 3px; cursor: pointer; }
.tab { width: 52px; height: 40px; background: transparent; border: 0; border-radius: 3px; color: var(--ink); font-size: 18px; cursor: pointer; }
.tab.on { background: var(--or); }
.rbody { flex: 1; min-height: 0; overflow-y: auto; display: grid; grid-template-columns: 1.1fr 1fr; gap: 18px; padding: 0 16px; }
.rbody.one { grid-template-columns: 1fr; }
.bul { margin: 4px 0 10px; padding-left: 20px; line-height: 1.55; }
.stages-bul b { font-weight: 800; }
.set-label { font-weight: 700; margin: 6px 0; }
.selector { display: grid; grid-template-columns: 44px 1fr 44px; align-items: center; background: #0f1013; border-radius: 4px; margin-bottom: 10px; }
.selector button { height: 64px; background: transparent; border: 0; color: var(--ink); font-size: 26px; cursor: pointer; }
.selector button:hover { color: var(--or); }
.sel-val { text-align: center; padding: 6px 0; }
.sel-val small { display: block; color: var(--dim); }
.dots { display: flex; gap: 4px; justify-content: center; margin-top: 6px; }
.dots span { width: 36px; height: 3px; background: #444; }
.dots span.on { background: var(--or); }
.toggle-row { display: flex; align-items: center; justify-content: space-between; padding: 12px 12px; margin-bottom: 4px;
  background: rgba(255,255,255,.04); border-radius: 3px; cursor: pointer; }
.toggle-row:hover { background: rgba(255,255,255,.08); }
.toggle { width: 34px; height: 16px; border-radius: 8px; background: #555; position: relative; flex: none; }
.toggle .knob { position: absolute; top: 2px; left: 2px; width: 12px; height: 12px; border-radius: 50%; background: #ddd; transition: left .15s; }
.toggle.on { background: var(--or); }
.toggle.on .knob { left: 20px; background: #fff; }
.rtable { width: 100%; border-collapse: collapse; }
.rtable th { text-align: left; font-style: italic; color: var(--dim); padding: 6px 8px; border-bottom: 1px solid var(--hair); }
.rtable td { padding: 9px 8px; border-bottom: 1px solid var(--hair); }
.rcol .go-btn.bottom { margin: 12px 16px 0; width: calc(100% - 32px); flex: none; }
.scol { display: flex; flex-direction: column; min-height: 0; padding: 4px 14px 14px; }
.slist { flex: 1; overflow-y: auto; display: grid; gap: 8px; align-content: start; }
.stage { display: grid; grid-template-columns: 120px 1fr; gap: 12px; padding: 6px; border: 2px solid transparent; border-radius: 4px;
  background: #15161a; color: var(--ink); text-align: left; cursor: pointer; font: inherit; }
.stage:hover, .stage.on { border-color: var(--or); }
.stage.run { box-shadow: inset 4px 0 0 #17c936; }
.sart { height: 90px; }
.sname { font-weight: 800; font-size: 17px; display: flex; align-items: center; gap: 8px; }
.plate { background: var(--or); color: #fff; font-size: 12px; font-weight: 800; padding: 2px 6px; border-radius: 2px; }
.smeta { color: var(--dim); font-size: 13.5px; margin-top: 3px; }
.sactions { display: flex; gap: 8px; margin-top: 10px; flex-wrap: wrap; }
.btn { flex: 1; padding: 10px; border: 1px solid var(--hair); border-radius: 3px; background: var(--panel2); color: var(--ink); font: inherit; font-weight: 700; cursor: pointer; }
.btn:hover { border-color: var(--or); }
.btn:disabled { opacity: .45; }
.btn.danger { background: #b9282d; border-color: #b9282d; }
.modes { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; margin: 10px 0 2px; }
.modes button { padding: 10px; border: 1px solid var(--hair); border-radius: 3px; background: var(--panel2); color: var(--ink);
  font: inherit; font-weight: 800; font-style: italic; font-size: 16px; cursor: pointer; }
.modes button.on { background: var(--or); border-color: var(--or); }
.modes button:disabled { opacity: .4; cursor: default; }
.stage.itin { grid-template-columns: 70px 1fr; align-items: center; }
.stage.itin.dimmed { opacity: .45; }
.stage:disabled { cursor: default; }
.plate.tc { background: #1e88d6; font-size: 15px; text-align: center; padding: 6px 0; }
.sname .plate { margin-left: 8px; }
.chips-row { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px; }
.foot { margin-top: 18px; }
.sectx { font-style: normal; font-weight: 400; }
.recmod { margin: 2px 0 6px; font-size: 0.82em; opacity: 0.85; line-height: 1.35; .ok { color: #7bd88f; } .warn { color: #ffb347; } a { color: #ff8a3d; margin-left: 4px; } }
.newimp { border: 1px solid rgba(255,255,255,0.12); border-radius: 6px; padding: 8px 10px; margin: 6px 0 10px; }
.newimp input[type=file] { color: inherit; font-size: 0.85em; }
.go-btn.danger { background: #b3261e; }
</style>
