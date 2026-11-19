# Normas del montaje (todos los tramos, actuales y futuros)

El tramo de referencia es **Obejo** (43 Rally Sierra Morena 2026), comprobado en los dos sentidos.

- **Calzada libre:** nada en la calzada salvo conos en el eje, y solo en doble sentido. Carteles, sensores y banderines van entre la línea continua y el final del asfalto; las carpas siempre fuera, a un lado.
- **Medidas:** la línea continua de borde está en el radio del grafo de carreteras de BeamNG.Earth y el asfalto sigue unos 0,6 m más.
  - Centro de los carteles de línea: radio + 0,4 m (`SIGN_SIDE_M`).
  - Resto de carteles: radio + 0,5 m (`SIDE_PAD_M`).
- **Red de seguridad (`dressing.offRoad`):** todo objeto colocado (menos los conos) se comprueba contra la carretera más cercana y, si cae en su calzada, se saca hacia fuera.
  - Al colocarlo.
  - De nuevo cada 1,5 s al acercarse el jugador (`dressing.recheck`).
- **Mismo montaje en los dos sentidos (`dressing.endKit`):** cada extremo del tramo lleva lo mismo.
  - **La línea:** a cada lado, el cartel de meta 0,9 m por dentro (0,45 m más afuera) y el de salida 0,9 m por fuera, con los sensores en medio. Fin de zona a 25 m y aviso de meta lanzada a 100 m.
  - **Vallas y público:** de 30 m dentro a 25 m fuera.
  - **Puesto de control a D m por fuera:** es el TC de quien sale (D = 150 m; FIA: 50-200) y el STOP de quien llega (FIA: 150-300). Lleva aviso amarillo, tablillas 3-2-1 y médico.
  - **Lo que cambia con el sentido:** el semáforo de salida, el reloj de meta, el color de la línea y en qué carpa está el reloj de fichar.
- **Carretera de cada extremo (`stage.endRoad`):** el enlace del organizador que toca ese extremo; si no lo hay, el grafo de carreteras del juego.
- **Puestos de control:** en doble sentido, uno a cada lado. Cada uno con carpa 3×3, mesa del lado de la carretera, silla detrás mirando a la carretera, luz de noche, y el reloj LED en la carpa del sentido que se corre.
- **Alineación:** todo se apoya en el eje de la carretera del juego (`dressing.snap`), no en la línea del archivo. Las líneas de TC, salida, meta y STOP quedan perpendiculares a la calzada y de borde a borde.
- **Señalización FIA** (Anexo I, señalización de controles):
  - Amarillo → al menos 25 m → control rojo.
  - Aviso amarillo 100 m antes de la meta lanzada.
  - STOP 150-300 m después de la meta.
  - Radio y médico con preaviso a 100 m, en los dos sentidos.
- **Cintas de corte:** nunca en la carretera del tramo. Sus estacas quedan a más de radio + 1,2 m de ella.
- **Dirección de salida y de meta (`clean.hooks`):** un gancho en los primeros o los últimos 80 m del trazado (la línea se vuelve sobre sí misma, giro ≥ 150°: Villaviciosa empezaba 33 m hacia atrás) se quita antes de montar nada. Si no, la salida queda mirando al revés: semáforo de espaldas, línea por delante del punto 0 y «colocado» imposible. En mitad del tramo no se toca: allí es una horquilla.
- **Pantalla de carga primero (`loader.cover`):** al iniciar, reiniciar o abandonar, nada se mueve ni se quita hasta que la pantalla tapa el juego; mientras está, las apps de pantalla (minimapa incluido) quedan ocultas.
- **Filas (vallas, lonas, mallas):** cada pieza a su paso medido sobre el terreno (vallas: 2,75 m), no sobre el eje. Si en su sitio hay un árbol, un muro o una calle, se deja el hueco: nunca se desplaza encima de sus vecinas. Además, vallas, carpas y ambulancias guardan una separación mínima entre centros (`dressing.MIN_GAP_M`).
- **Puesto médico (`dressing.medicPost`):** con una calle lateral a menos de 70 m, dentro de ella y cortada (cinta, barreras, ambulancia mirando al tramo, carpa con mesa y silla). Sin calle, la ambulancia fuera de la calzada con toda su planta libre (6,2 × 2,4 m); si no cabe, no se pone.
- **Ventana de la cámara del reloj:** debajo de la tarjeta STAGED del juego (`startclock.TOP_RATIO = 0.225`).
- **Teletransporte:** a la calzada, 100 m antes del TC y mirando hacia él.
- **Notas del copiloto:** el grado sale del radio mínimo en 24 m. En marcha, las curvas se vuelven a medir sobre la carretera real del juego.
- **Reloj LED:** la hora real y la cuenta atrás hasta la hora de salida fijada en el TC.

## Banderas
`earthRaid/flags/*.png` (30×20): banderas de países por código ISO 3166-1 alfa-2, para el menú. Las banderas nacionales son de dominio público.
