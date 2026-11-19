// Raid.Earth: la página del menú como ruta propia ("earthRaid", la abre earthRaid_main.uiOpen con ui_router.navigate)
// y un botón en la pestaña Mods del menú de pausa. Sigue ui/ui-vue/mods/README.md del juego.
import { lua } from "@/bridge"
import { createApp } from "vue"

const MOD_ROOT = "/ui/ui-vue/mods/earthRaid"
const SOURCE = "earthRaid.routes"
const BUTTON_ID = "earthRaid-open"

function toLuaRoutes(records) {
  return records.map(record => ({ name: record.name, path: record.path, meta: record.meta }))
}

async function registerRoute() {
  try {
    if (!window.bngRoutes || !lua.extensions.ui_router_routeManager) return
    const RaidMenu = (await import("./RaidMenu.vue")).default
    const StartScreen = (await import("./StartScreen.vue")).default
    const routes = [
      {
        path: "/earth-raid",
        name: "earthRaid",
        component: RaidMenu,
        meta: { luaRoute: { title: "Raid.Earth", backTarget: "play" } },
      },
      // la pantalla de inicio tras la carga (resumen, normas, ajustes, Iniciar); atrás: la ficha del evento
      {
        path: "/earth-raid-start",
        name: "earthRaidStart",
        component: StartScreen,
        meta: { luaRoute: { title: "Raid.Earth", backTarget: "earthRaid" } },
      },
    ]
    window.bngRoutes.add([{ path: SOURCE, routes }])
    const result = await lua.extensions.ui_router_routeManager.registerModRoutes(SOURCE, toLuaRoutes(routes))
    if (!result?.success) {
      window.bngRoutes.remove([SOURCE])
      console.error("Raid.Earth: route not registered", result?.errors)
    }
  } catch (e) {
    console.error("Raid.Earth: route failed", e)
  }
}

// Raid.Earth en el menú de pausa (Esc) con su propia pestaña, como BeamNG.Earth y BeamMP (petición del usuario,
// 17-nov: "que parezca una parte más del juego"): botones a la izquierda (Eventos, Importar, Ajustes) y el estado del
// tramo en la tarjeta de la derecha. Ya no hay atajo Ctrl+Mayús+G (chocaba con el de las gráficas del juego).
const TAB_ID = "earthRaid"
const PAGES = [
  { id: "earthRaid-events", page: "events", label: { es: "Eventos", en: "Events" }, icon: "rallyHelmet" },
  { id: "earthRaid-import", page: "import", label: { es: "Importar", en: "Import" }, icon: "import" },
  { id: "earthRaid-settings", page: "settings", label: { es: "Ajustes", en: "Settings" }, icon: "cogOutline" },
]
// el idioma del juego (español o inglés)
async function gameLang() {
  try { const l = await lua.earthRaid_main.uiLang(); return l === "es" ? "es" : "en" } catch (e) { return "en" }
}
async function registerButton() {
  try {
    const pa = lua.extensions.ui_pause_actions
    // el botón antiguo de la pestaña Mods
    try { await pa.unregisterModButton(BUTTON_ID) } catch (e) { /* none */ }
    await pa.registerModTab({
      id: TAB_ID,
      label: "Raid.Earth",
      icon: "rallyHelmet",
      card2ComponentName: `${MOD_ROOT}/PausePage.vue`,
      card2Props: { page: "status" },
    })
    const lang = await gameLang()
    for (const p of PAGES) {
      await pa.registerModButton({
        id: p.id, tabId: TAB_ID, label: p.label[lang] || p.label.en, icon: p.icon,
        componentName: `${MOD_ROOT}/PausePage.vue`, props: { page: p.page },
      })
    }
  } catch (e) {
    console.error("Raid.Earth: pause menu tab failed", e)
  }
}

// la pantalla de carga de Raid.Earth: una capa propia sobre toda la interfaz (no depende de que la app del HUD esté
// en el diseño de pantalla)
const LOAD_ID = "earthRaid-loadscreen"
let loadApp = null
async function mountLoadScreen() {
  try {
    if (loadApp || document.getElementById(LOAD_ID)) return
    const LoadScreen = (await import("./LoadScreen.vue")).default
    const el = document.createElement("div")
    el.id = LOAD_ID
    document.body.appendChild(el)
    loadApp = createApp(LoadScreen)
    loadApp.mount(el)
  } catch (e) {
    console.error("Raid.Earth: load screen failed", e)
  }
}

// Con un tramo o un rally en marcha, al abrir el menú de pausa se abre la pestaña de Raid.Earth (abandonar, reiniciar)
let pauseObserver = null
let pauseSeen = false
function watchPause() {
  if (pauseObserver) return
  let busy = false
  pauseObserver = new MutationObserver(() => {
    // como mucho cada 400 ms (la interfaz cambia muchas veces por segundo)
    if (busy) return
    busy = true
    setTimeout(() => { busy = false; checkPause() }, 400)
  })
  pauseObserver.observe(document.body, { childList: true, subtree: true })
}
async function checkPause() {
  {
    const tab = [...document.querySelectorAll("span,div,button")].find(e => e.children.length < 3 && e.textContent.trim() === "Raid.Earth" && e.offsetParent)
    if (!tab) { pauseSeen = false; return }
    if (pauseSeen) return
    pauseSeen = true
    try {
      if (await lua.earthRaid_main.uiIsActive()) (tab.closest("button,[role=tab],a,li,div") || tab).click()
    } catch (e) { /* none */ }
  }
}

export async function onLoad() {
  await registerRoute()
  await registerButton()
  await mountLoadScreen()
  watchPause()
}

export async function onUnload() {
  try { if (pauseObserver) { pauseObserver.disconnect(); pauseObserver = null } } catch (e) { /* none */ }
  try {
    if (loadApp) { loadApp.unmount(); loadApp = null }
    const el = document.getElementById(LOAD_ID)
    if (el) el.remove()
  } catch (e) { /* none */ }
  try { await lua.extensions.ui_pause_actions.unregisterModTab(TAB_ID) } catch (e) { /* none */ }
  try {
    if (window.bngRoutes) window.bngRoutes.remove([SOURCE])
    if (lua.extensions.ui_router_routeManager) {
      await lua.extensions.ui_router_routeManager.unregisterModRoutes(SOURCE, { fallbackRoute: "play" })
    }
  } catch (e) {
    console.error("Raid.Earth: unload failed", e)
  }
}
