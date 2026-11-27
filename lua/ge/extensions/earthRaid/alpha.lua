-- Earth.Raid: funciones en ALPHA, apagadas por defecto para que el rally sea lo más estable posible (23-nov, orden del usuario:
-- «todo el tema de repintar o remodelar el terreno lo dejamos como alpha y lo seguiremos investigando más adelante»).
-- Para investigarlas: poner TERRAIN_EDIT = true (recargar Lua con Ctrl+L y reiniciar el tramo).
local M = {}

-- true: los caminos generados remodelan y repintan el terreno (explanada, río helado, charcos en hoyo), los bancos de nieve
-- levantan el terreno y repintan el barro, y se dibujan las rodadas/charcos (decals) a lo largo del tramo.
-- false: el terreno de Earth no se toca. Siguen funcionando: HUD, relojes, señales, bidones, vallas, despeje de árboles y
-- objetos en la calzada, copiloto, cronometraje, línea guía, etc.
M.TERRAIN_EDIT = false

return M
