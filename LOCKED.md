# Archivos y comportamientos BLOQUEADOS (orden del usuario, 23-nov)

Regla: lo que el usuario ha dicho que funciona NO se toca sin su permiso expreso. Antes de cualquier cambio que afecte a
algo de esta lista, avisar de las dependencias y esperar el visto bueno. Comprobar con `tools/check_locks.sh`.

| Bloqueado | Archivo | Lo que se aprobó |
|---|---|---|
| Reloj de salida (semáforo) | `startclock.lua` | posición/cámara, tiempos unificados Staged/Skip/reloj, lado derecho |
| Pantalla de carga y reinicio rápido | `loader.lua` | pasos cover/tp/roads/dress/place/settle, `L.fast` (26-nov: el usuario dio permiso para optimizar la carga) |
| HUD (apps del rally del juego) | `vhud.lua` | 27-nov: revisado en asistencia (límite 30), enlace, TC, camino a la salida (SSn), staged, cuenta atrás, tramo, meta (SLOW + distancia) y STOP; sin «STOP 0.0m» en el enlace |

## Dependencias (avisar antes de tocar)
- `vhud.lua` lee el estado de `stage.lua` (`S.phase`, `S.distM`, `S.startAt`, `S.tcDue`, `S.line`) y de `rally.lua` (`R.phase`, `R.it.items`, `R.startAt`, `R.rows`). Cambiar esos campos o las fases afecta al HUD.
- `startclock.lua` lo usan `stage.lua` (arranque, `S.startAt`, `S.stagingLeft`) y `vhud.lua`. No cambiar sus firmas.
  Si cambia la geometría de la salida (`dressing.lua`: línea de salida, lado derecho de la calzada) el reloj se ve afectado.
- `loader.lua` lo usan `main.lua` (`uiPlay`, `uiStartRally`, pantalla de carga), `stage.lua`, `dressing.lua` y `audit.lua`; usa `props.lua`.
  Cambios en el orden de montaje de `dressing.lua` o en `servicepark.lua` pueden alterar la carga.
