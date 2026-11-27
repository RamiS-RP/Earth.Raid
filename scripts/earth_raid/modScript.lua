-- Se ejecuta cuando el mod se monta (core/modmanager.lua): carga la extensión principal y la deja cargada entre
-- niveles ('manual'). Sin esto, instalado como .zip el menú de Earth.Raid no aparecía.
if extensions and extensions.load and not rawget(_G, 'earthRaid_main') then
  pcall(extensions.load, 'earthRaid_main')
end
setExtensionUnloadMode('earthRaid_main', 'manual')
