# Earth.Raid en BeamMP (BeamNG.Earth multijugador): plan

18-nov. Objetivo: un rally virtual en un servidor BeamMP con BeamNG.Earth. Los jugadores salen por orden y el servidor guarda los tiempos. Sin coste de rendimiento para los demás jugadores ni para el servidor.

## Principio: el servidor decide y cronometra; cada cliente monta y dibuja lo suyo
- **Ningún objeto viaja por la red.** Cada cliente genera el montaje él mismo: mismo evento, mismo algoritmo y mismos datos de BeamNG.Earth, así que todos ven lo mismo. El servidor solo envía el id del evento, el tramo, el sentido y una **semilla** (público, colores, variantes).
- **Los objetos con física (carteles, conos, cinta) son vehículos en BeamNG.** BeamMP sincroniza cada vehículo nuevo, así que deben ser locales (no enviados) o quedarse estáticos en multijugador. Con ~30 por cliente a menos de 220 m, sincronizarlos llenaría la red de todos.
- **El servidor no simula nada.** Un plugin Lua de BeamMP recibe unos pocos mensajes por jugador y tramo, nunca por fotograma: inscripción, TC, salida, parciales, meta y penalizaciones. Son unos 10 mensajes de menos de 200 bytes por tramo y jugador.

## Mensajes (TriggerServerEvent / TriggerClientEvent, JSON pequeño)
| Mensaje | Quién | Cuándo | Contenido |
|---|---|---|---|
| er_event | servidor → todos | al abrir el evento / al entrar alguien | evento, tramos, sentido, semilla, primera salida, intervalo (1-2 min), estado |
| er_join | cliente → servidor | se apunta | nombre, coche (modelo + config) |
| er_order | servidor → todos | al cerrar inscripción y tras cada tramo | orden y hora de salida de cada uno |
| er_tc | cliente → servidor | ficha en el TC | hora del reloj del rally (la del servidor) |
| er_start | servidor → cliente | su minuto | hora exacta de salida; la cuenta atrás va en local |
| er_split | cliente → servidor | cada parcial | tiempo |
| er_finish | cliente → servidor | meta | tiempo, penalizaciones, suma de control |
| er_board | servidor → todos | tras cada meta | clasificación del tramo y general (solo cambios) |

- **Reloj:** el servidor manda su hora. Cada cliente estima su diferencia con la mitad de la ida y vuelta y cronometra en local (`os.clockhp`). La latencia no afecta al tiempo; el servidor solo comprueba que sea coherente.
- **Anti-trampas:**
  - `guard.lua`: no se puede cambiar de coche ni teletransportarse.
  - El servidor rechaza tiempos imposibles (distancia / 250 km/h) y parciales fuera de orden.
  - Suma de control con tiempo, tramo, parciales y semilla.
- **Salida escalonada:** cada uno en su minuto. Opción de ocultar a los jugadores que no están en tu tramo para ganar fotogramas.

## Rendimiento
- **Cliente:** solo se monta tu tramo (o al que vas), como en un jugador. Sin IA de tráfico en el tramo (`stage.trafficOff`).
- **Servidor:** una tabla en memoria por evento y un JSON al acabar cada tramo. Temporizadores de 1 s para las salidas.

## Clasificación
- **Fase 1, en el servidor:** `Resources/Server/EarthRaid/results/<evento>.json`. En el juego se ve con la hoja de tiempos (`rallyTimecard`) y con una tabla como la de las misiones (`MissionLeaderboards.vue`).
- **Fase 2, global (opcional):** el plugin del servidor manda los resultados a un servicio web gratuito (Supabase o Cloudflare Worker + D1) con una clave del servidor. Los clientes nunca escriben ahí directamente.

## Fases
1. **Cliente en modo multijugador:** detectar BeamMP (`MPGameNetwork`/`MPVehicleGE`); objetos con física solo locales; semilla; reloj sincronizado.
2. **Plugin del servidor** (`Resources/Server/EarthRaid/main.lua`): eventos, inscripción, orden y horas de salida, validación de tiempos, clasificación.
3. **UI:** hoja de tiempos y panel con los datos del servidor; tabla de clasificación; aviso «tu salida en 2 min».
4. **Pruebas:** servidor local de BeamMP con dos clientes y después un servidor real.

## Decidido (18-nov)
- Servidor propio del usuario, ya en marcha, para **20 jugadores** de momento. Se desarrolla en **beta**.
- **Salidas cada 1 minuto** por defecto; el admin del servidor puede cambiarlo (comando o archivo de configuración del plugin).
- **Dos clasificaciones:** la del servidor y una global (para cuando se use en otros servidores).
- De momento es solo planificación; antes, pulir el generador de tramos.
