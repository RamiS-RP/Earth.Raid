# Archivos y comportamientos BLOQUEADOS (orden del usuario, 23-nov)

Regla: lo que el usuario ha dicho que funciona NO se toca sin su permiso expreso. Antes de cualquier cambio que afecte a
algo de esta lista, avisar de las dependencias y esperar el visto bueno. Comprobar con `tools/check_locks.sh`.

| Bloqueado | Archivo | Lo que se aprobó |
|---|---|---|
| Reloj de salida (semáforo) | `startclock.lua` | posición/cámara, tiempos unificados Staged/Skip/reloj, lado derecho |
| Pantalla de carga y reinicio rápido | `loader.lua` | pasos cover/tp/roads/dress/place/settle, `L.fast` |

## Dependencias (avisar antes de tocar)
- `startclock.lua` lo usan `stage.lua` (arranque, `S.startAt`, `S.stagingLeft`) y `vhud.lua`. No cambiar sus firmas.
  Si cambia la geometría de la salida (`dressing.lua`: línea de salida, lado derecho de la calzada) el reloj se ve afectado.
- `loader.lua` lo usan `main.lua` (`uiPlay`, `uiStartRally`, pantalla de carga), `stage.lua`, `dressing.lua` y `audit.lua`; usa `props.lua`.
  Cambios en el orden de montaje de `dressing.lua` o en `servicepark.lua` pueden alterar la carga.
