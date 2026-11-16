// Raid.Earth: la página del menú como ruta propia ("earthRaid", la abre earthRaid_main.uiOpen con ui_router.navigate)
// y un botón en la pestaña Mods del menú de pausa. Sigue ui/ui-vue/mods/README.md del juego.
import { lua } from "@/bridge"

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
    const routes = [
      {
        path: "/earth-raid",
        name: "earthRaid",
        component: RaidMenu,
        meta: { luaRoute: { title: "Raid.Earth", backTarget: "play" } },
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

async function registerButton() {
  try {
    await lua.extensions.ui_pause_actions.registerModButton({
      id: BUTTON_ID,
      tabId: "mods",
      label: "Raid.Earth",
      icon: "raceFlag",
      componentName: `${MOD_ROOT}/PauseCard.vue`,
    })
  } catch (e) {
    console.error("Raid.Earth: pause menu button failed", e)
  }
}

export async function onLoad() {
  await registerRoute()
  await registerButton()
}

export async function onUnload() {
  try { await lua.extensions.ui_pause_actions.unregisterModButton(BUTTON_ID) } catch (e) { /* none */ }
  try {
    if (window.bngRoutes) window.bngRoutes.remove([SOURCE])
    if (lua.extensions.ui_router_routeManager) {
      await lua.extensions.ui_router_routeManager.unregisterModRoutes(SOURCE, { fallbackRoute: "play" })
    }
  } catch (e) {
    console.error("Raid.Earth: unload failed", e)
  }
}
