# Progreso del proyecto · Crazy Mototaxi

Seguimiento de lo pedido en `Crazy_Mototaxi_Semana10.pdf` (cronograma S11–S15).
Actualizar este archivo cada vez que se cierre una tarea.

**Ramas**
- Desde el 2026-11-04 la jugabilidad se trabaja en `juego` (avanzada hasta `main` 036c432); `main` queda para
  el entorno y la parte gráfica de los demás integrantes.
- `main`: terreno y realismo (erosión multiescala del paper *Terrain Amplification using Multi-scale Erosion*).
- `juego`: jugabilidad (vehículo, carreras, HUD). Desde el 2026-10-19 incluye `origin/main` (merge) y el juego
  corre sobre el terreno de CG (regiones, erosión, drenaje/ríos, red vial, texturas e iluminación).

Leyenda: ✅ hecho · 🟡 en curso / parcial · ⬜ pendiente

---

## Jugabilidad (rama `juego`)

### S11 — Hito: "Mototaxi manejable que recoge a un pasajero"

| Rol | Tarea | Estado | Dónde |
|---|---|---|---|
| CG-B | API `TerrainWorld` (`generate`, `get_height`, `get_normal`, `get_biome`, `get_drainage`, `get_landmarks`, `find_route`) | ✅ sobre el generador real de CG (`chunk_mesh.gd`) | `project/scripts/terrain_world.gd` |
| J-A | Mototaxi con `VehicleBody3D` (3 ruedas), controles teclado/mando | ✅ | `project/scenes/mototaxi.tscn`, `project/scripts/mototaxi.gd` |
| J-A | Cámara de persecución que no atraviesa el terreno | ✅ | `project/scripts/chase_camera.gd` |
| J-A | Probada en el terreno actual (enderezado automático y con R) | ✅ | `project/tests/test_mototaxi.gd` |
| J-B | Estados de carrera: libre, con pasajero, entregado, fallado | ✅ | `project/scripts/race_manager.gd` |
| J-B | Zonas de recogida/destino con `Area3D` (zonas brillantes provisionales) | ✅ | `project/scripts/glow_zone.gd` |
| J-B | Temporizador (límite = 15 s + largo de ruta A* a 30 km/h) | ✅ | `RaceManager.compute_time_limit()` |
| J-B | HUD básico: velocidad, objetivo, distancia, tiempo, entregas/fallidas, flecha al objetivo, anuncios | ✅ | `project/scripts/race_hud.gd` |

**Cómo funciona el ciclo (S11)**
1. **Libre**: aparece una zona **amarilla** (pasajero) en un landmark a 30–180 m.
2. Entrar a la zona a **menos de 20 km/h** sube al pasajero → **Con pasajero**.
3. Aparece la zona **verde** (destino); arranca el temporizador. Desde 2026-11-06 el viaje puede ser corto
   (80–300 m), medio (300–800 m) o largo (800–1900 m, cruza el mapa) — ver pendiente 8.
4. Llegar a tiempo → **Entregado** (+1 entrega). Se acaba el tiempo → **Fallado** (+1 fallida).
5. Tras 3 s de anuncio aparece un nuevo pasajero.

Los parámetros (distancias, velocidad de abordaje, tiempo base, colores) son `@export` del nodo `RaceManager` en `main.tscn`.

### S12 — Hito: "Partida completa que termina por tiempo o por vida"

| Rol | Tarea | Estado |
|---|---|---|
| J-A | Vida: daño por choque (cambio brusco de velocidad en un paso) | ✅ `Mototaxi.apply_damage`, `crash_threshold` |
| J-A | Vuelco = daño (20), fin de partida y reinicio | ✅ `GameSession`, `GameOverScreen`, `main.restart()` |
| J-A | Fin por salir del mapa o quedar atrapada (acelera sin moverse 12 s, aviso 5 s antes) | ✅ `GameSession` |
| J-B | Ruta dibujada en el mundo, **por las vías** (A* sobre el grafo de vías) | ✅ `RouteLine`, `RoadRouter`, `TerrainWorld.find_road_route` |
| J-B | Flecha de navegación que sigue la ruta; se recalcula si te desvías (atajo) | ✅ `RaceManager.get_guide_point` |
| J-B | Tiempo límite según largo **y pendiente** de la ruta | ✅ `RaceManager.compute_route_time` |
| — | Fin de partida por N fallos (3) | ✅ |

### S13 — Integración

| Rol | Tarea | Estado |
|---|---|---|
| J-A | Integrar con la API real; ajustar suspensión y agarre en terreno erosionado | ✅ (ver "Integración terreno de CG + juego") |
| J-B | Integrar con la API real | ✅ |
| J-B | Pasajero que se enoja (golpes, vuelcos, tiempo), propina y puntaje en soles | ✅ `RaceManager` (ánimo, `paid`), HUD |
| CG/J | Región elegida en el menú: mayoría o solo costa/sierra/selva (`biome_bias` en C++) y empezar en ella | ✅ |
| J-B | Pasajeros reales (modelo/personaje) en lugar de zonas brillantes | ✅ `Passenger`: 6 personas animadas (Quaternius, CC0) que esperan, hacen señas, suben, pagan o reclaman y se van |
| CG-B | Landmarks automáticos por tipo (picos, confluencias, costa) | ✅ `find_landmark_features` (ver `docs/s12_s14_cg.md`) |

### S14 — Pulido

| Rol | Tarea | Estado |
|---|---|---|
| J-A | Sonido de motor y choques; balance de vida y daño | 🟡 sonido ✅ motor por vehículo (`VehicleEngineAudio`, garaje) + golpes y rodadura (`MototaxiAudio`); falta balance |
| J-B | Menú con semilla | ✅ menú previo (terreno guardado o semilla, calidad, región, garaje) |
| J-B | Minimapa a partir del heightmap | ✅ `Minimap` (estilo GTA: gira con la mototaxi, relieve, ríos, vías, ruta y objetivo) |
| J-B | Pantalla final con puntaje | ✅ `GameOverScreen` |
| CG/J | Vegetación con modelos reales, troncos sólidos que dañan al chocar | ✅ `VegetationModels`, `NearVegetation`, `TreeColliders` |
| CG | Impostores octaédricos para los árboles lejanos (horneado propio + shader) | ✅ `VegetationImpostors`, `tools/bake_impostors.gd` |
| J | Menú de pausa: continuar, reiniciar turno, volver al menú sin perder, volumen | ✅ `PauseMenu` (Esc / P / Start) |

### Pendientes de jugabilidad (inspirados en los minijuegos de taxi de GTA)

Idea general: copiar la *jugabilidad* de GTA (no su escala). Orden sugerido de abajo hacia arriba.

| # | Pendiente | Estado |
|---|---|---|
| 1 | Quitar las guías en el mundo: cinta con flechas (a veces al revés) y columnas/discos de luz que seguían junto al cliente | ✅ cinta oculta (`RaceManager.show_route_in_world = false`), recogida sin marcador, destino = anillo plano sobre el suelo, sin luz |
| 2 | Minimapa estilo GTA como guía principal (ruta por las vías + punto del objetivo) | ✅ `Minimap` en `RaceHUD`; se quitó la flecha flotante |
| 3 | Mapa completo (tecla M o en la pausa), estilo GTA, con el destino y la ruta | ✅ `FullMap` (M / Back): norte arriba, zoom y arrastre, lugares con nombre; pausa el juego |
| 4 | Darle sentido al dinero (ver opciones abajo) y un fin de partida que no dependa solo de la vida | ✅ opciones 1 + 3: jornadas con cuota (`GameSession`) y ahorros para el garaje (`CareerSave`); sin propinas |
| 5 | Obstáculos en el camino: animales que cruzan o caminan por la vía (estilo Mario Kart), según región: costa perros/gallinas, sierra llamas/alpacas/ovejas, selva chanchos/gallinas; chocar = daño y enojo del pasajero | ✅ 2026-11-08 `RoadAnimals` (ver "Pendiente 13 — fase B, cómo quedó") |
| 6 | Otros obstáculos en la vía: piedras de huaico, baches, charcos, otras mototaxis o combis lentas | ✅ 2026-11-08 obstáculos fijos (`RoadObstacles`, ver abajo); 2026-11-10 vehículos (`RoadTraffic`, pendiente 13 fase C) |
| 7 | Ordenar partidas (opción B, decidida 2026-11-06): una sola carrera continua + Modo libre; quitar "Nueva partida"; elegir el escenario al terminar el día o al reiniciar (ver abajo) | ✅ `ScenarioPicker`/`ScenarioPanel`, `CareerSave.launch`, `GameSession.free_mode` |
| 8 | Destinos por todo el mapa: viajes corto/medio/largo (≈50/32/18 %), los largos pagan más por km (hasta el doble) y rinden más por minuto; no se piden si no alcanza la jornada; en los largos se prefieren lugares con nombre | ✅ `RaceManager._pick_destination`, `compute_fare`, `time_budget`; prueba `tests/test_destinos.gd` |
| 9 | Minimapa para viajes largos: (a) la distancia del HUD es la que falta de la **ruta**, en km desde 1000 m; (b) el punto del objetivo pegado al borde se dibuja como flechita hacia afuera (como en GTA); (c) opcional, alejar más el minimapa a toda velocidad (p. ej. 300 m) si al jugar hace falta | ⬜ propuesto 2026-11-06 (a y b recomendados) |
| 10 | Red vial, paradas y ambientación: ver el plan "Red vial, paradas y ambientación" abajo | 🟡 fases 1–3 ✅; fase 4 🟡 (viviendas ✅, ambientación por tipo de parada ⬜); fase 5 ✅ (animales) |
| 11 | Elegir escenario con **vista previa** (costa, sierra, selva, mixto) en vez de solo el nombre, como en un juego | ✅ 2026-11-06 (revisado y aprobado por el usuario): `ScenarioPicker` con 4 tarjetas con foto (en una fila si hay espacio, si no 2×2); fotos del juego real con `tools/capture_scenario_previews.gd` → `ui/scenarios/*.jpg`; Mixta = collage diagonal de las tres |
| 13 | **Dificultad** fácil / normal / difícil (pedido 2026-11-08) en vez de elegir directamente la cantidad de obstáculos: que regule la frecuencia de obstáculos fijos, **animales** (fase 5) y **tráfico** (pendiente 6). Plan ordenado 2026-11-08: ver "Pendiente 13 — plan Dificultad y obstáculos que se mueven" abajo | 🟡 fase A ✅ y B ✅ 2026-11-08 (`Difficulty` por partida; animales `RoadAnimals`); C ✅ 2026-11-10 (tráfico `RoadTraffic`); falta D balance |
| 12 | Garaje dentro del **Modo libre** (cambiar de vehículo al momento, sin volver al menú), como ya se hace con el escenario | ✅ 2026-11-06: botón "Garaje" en la pausa del Modo libre (`PauseMenu.open_garage`, el mismo `VehicleGarage`); al volver o continuar se usa la mototaxi elegida (`garage_closed` → `Main._use_active_vehicle`) |

**Pendiente 6 — obstáculos fijos en las vías (hecho 2026-11-08)**
- `RoadObstacles` (`project/scripts/road_obstacles.gd`), lo arma `TerrainWorld._build_obstacles` después de
  las paradas. Seis tipos, elegidos por región (`get_biome`) y tipo de vía:
  - Sólidos (tapan un lado; chocar = frenazo brusco → `Mototaxi._check_crash`, daño y enojo):
    **rocas** de huaico/derrumbe (sierra; algo en costa), **tronco** caído (selva; eucalipto en sierra; en
    la selva con la copa al costado), **obra** (barriles naranja/blanco + conos de aviso a 9 m por los dos
    lados; los conos son `RigidBody3D` de 3 kg y se tumban sin daño).
  - Suelo (los consulta la mototaxi por rueda con `TerrainWorld.get_hazard`): **charco/barro** (sierra,
    selva) y **arena** que invade la pista (costa) frenan (`mud_drag`) y resbalan; **bache**: sacudón y daño
    `(km/h − 18) × 0.2` (≈ 5 a 45 km/h, razón `"bache"`; el pasajero: "¿No vio ese hueco?").
  - En las calles del pueblo casi solo baches y obras; en trochas no hay obras.
- Reglas: los sólidos tapan entre 45 y 62 % del ancho desde un borde (en la carretera llegan a la línea del
  centro) pero siempre queda un carril libre de ≥ 2.8 m (`FREE_LANE`); solo en tramos casi rectos (±20 m,
  < 34°) y con pendiente < 0.14, para verlos venir. Ninguno a < 16 m de una parada (recogida, destino,
  inicio), a < 14 m de un cruce, sobre un puente o cauce, ni a < 45 m de otro. Sale de la semilla del mundo.
- Cantidad: Ninguno / Pocos / Normal / Muchos. Desde el 2026-11-08 la da la **dificultad de la partida**
  (Fácil = Pocos, Normal = Normal, Difícil = Muchos; ver pendiente 13); se quitó la opción "Obstáculos en las
  vías" de Opciones y `GameSettings`. Argumento `--obstaculos=0..3` para forzarla. `TerrainWorld`
  trae 0 por defecto (las pruebas no los ven salvo que los pidan).
- Mallas generadas por código, juntas por baldosas de 192 m (3 capas: sólido, agua brillante, manchas con
  borde transparente); colisión con cilindros. Construirlos: ~0.15 s en el mapa guardado.
- Mapa guardado (semilla 2, casi todo selva), nivel Normal: 64 obstáculos en 17.6 km de vías (24 troncos,
  21 charcos, 7 baches, 6 obras, 6 rocas). En la sierra salen pocos sólidos: las vías son curvas y empinadas.
- Pruebas: `tests/test_obstaculos.gd [-- semilla región]` (reparto por región, lugares, carril libre,
  misma semilla, barro frena, bache y roca dañan); `test_drive_routes -- 8 editor obstaculos` (el piloto
  los esquiva: 8/8 a tiempo). Capturas: `tests/capture_obstaculos.gd -- --editor --obstaculos=2` (con
  ventana) → `output/obstaculos/`.
- Ideas para después: vehículos lentos (combis, otras mototaxis), bocina que espanta animales (fase 5).

**Pendiente 13 — plan "Dificultad y obstáculos que se mueven" (planteado 2026-11-08)**

Pregunta del usuario: ¿hacen falta animales y otros vehículos si los obstáculos fijos ya dan dificultad?
Meta: en Difícil debe ser posible llegar tarde con una probabilidad considerable, y que eso salga de lo que
hay en el camino (esquivar, frenar, adelantar), no sobre todo de recortar el tiempo.

*Análisis*
- Los obstáculos fijos sirven, pero **se aprenden**: salen de la semilla (mismo mapa = mismo lugar), solo en
  tramos rectos para verlos venir, siempre con un carril libre de ≥ 2.8 m. El piloto automático los esquiva
  8/8 a tiempo. Le cuestan poco tiempo a un jugador que ya los conoce → no bastan para que Difícil falle.
- Lo que se mueve **no se aprende**: cada viaje es distinto. Es lo que da la tensión del taxi de GTA
  (gente y tráfico). Por eso sí hacen falta, pero con papeles distintos:
  - **Animales** = riesgo de **choque** (aparecen de costado, cruzan; daño + enojo). Eventos cortos. Le dan
    identidad a cada región (costa perros/gallinas, sierra llamas/alpacas/ovejas, selva chanchos/gallinas).
  - **Tráfico** (combis y otras mototaxis) = pérdida de **tiempo**: una combi lenta en una vía angosta obliga
    a ir detrás o arriesgarse a adelantar; los que vienen de frente hacen peligroso adelantar. Es lo que más
    pesa en llegar tarde. Ejemplo: 200 m detrás de una combi a 20 km/h en vez de 30 → ~12 s perdidos, casi
    todo el margen fijo de 15 s de un viaje corto.
- **Tiempo.** El límite (15 s + ruta a 30 km/h con castigo por subida) no cuenta los obstáculos, así que más
  obstáculos ya lo vuelven más estrecho solo. No se recorta más en Normal/Difícil; Fácil da algo de aire.

*Tabla de dificultad (valores iniciales, se ajustan en la fase D)*

| | Fácil | Normal | Difícil |
|---|---|---|---|
| Obstáculos fijos (`RoadObstacles.LEVELS`) | Pocos | Normal | Muchos |
| Animales | pocos, lentos, se apartan antes | algunos | frecuentes; rebaños en la sierra |
| Tráfico | poco, siempre en su carril | algo | más; combis que paran en paraderos, de frente en vías angostas |
| Tiempo límite | × 1.2 | × 1.0 | × 1.0 (× 0.9 solo si las pruebas muestran que no alcanza) |
| Pago (decidido 2026-11-08) | × 0.9 | × 1.0 | × 1.25 (premio por el riesgo) |

*Fases (en este orden)*
- **A. Dificultad de la partida** ✅ (2026-11-08). Decidido: es **de la partida**, no una opción general (se
  elige al empezar y se mantiene; para cambiarla hay que empezar otra), y más difícil paga más.
  - `Difficulty` (`project/scripts/difficulty.gd`): tabla `LEVELS` con nombre, texto, `obstacles`, `time`,
    `fare`, `animals` y `traffic` (estos dos para B y C, todavía sin efecto).
  - Viaja en el escenario elegido (`choice["difficulty"]`) y se guarda con la partida (`data["choice"]`);
    partidas viejas sin ella = Normal.
  - `ScenarioPicker`: fila "Dificultad" con su explicación. Se elige en Jugar, al perder ("Empezar en otro
    escenario"), en la pausa ("Reiniciar partida") y en el Modo libre; al terminar el día ("Escenario del día
    N") sale **bloqueada** con el aviso "para cambiarla, empieza una partida nueva". `same()` la compara:
    otra dificultad = otro escenario (se regenera el mapa, cambian los obstáculos). `describe()` la agrega
    ("Terreno guardado · Selva · Difícil").
  - `Main`: `world.obstacle_level` sale de la dificultad (o de `--obstaculos`), `RaceManager.time_factor` y
    `fare_factor` multiplican el tiempo límite y la tarifa; el anuncio de cada día muestra la dificultad.
    Argumento `--dificultad=0|1|2`. En el Modo libre solo cambia lo que hay en el camino.
  - Prueba: `tests/test_dificultad.gd` (tabla, factores, selector bloqueado, Main en Difícil y guardado).
- **B. Animales** ✅ (2026-11-08) = la fase 5 del pendiente 10, con su cantidad tomada de la tabla. Ver
  "Pendiente 13 — fase B, cómo quedó" abajo.
- **C. Tráfico** ✅ (2026-11-10; ver "Pendiente 13 — fase C, cómo quedó" abajo). Plan original: vehículos que recorren la red vial (`RoadRouter`) por su carril:
  - Cinemáticos (`AnimatableBody3D` que sigue la línea de la vía con la altura de `get_height`), no
    `VehicleBody3D`: barato y no se vuelcan. Frenan si hay algo delante (la mototaxi, un obstáculo, otro
    vehículo); esquivan los obstáculos fijos por el carril libre.
  - Tipos: otras mototaxis (se pueden reusar los modelos del garaje), combi lenta (más ancha), en sierra
    algún camión. Aparecen a 80–200 m de la mototaxi y se quitan lejos, como los animales.
  - Chocarlos = daño y enojo (`apply_damage(…, "vehiculo")`), con tiempo de gracia entre golpes.
  - Nunca tapan la recogida ni el destino.
- **D. Balance y medición.** Prueba sin ventana por dificultad (`tests/test_dificultad.gd`): el piloto hace
  N viajes por nivel y anota % a tiempo, segundos perdidos por km y golpes. Meta orientativa: Fácil ≈ todos a
  tiempo, Normal la mayoría, Difícil con una parte clara tarde (≈ 25–40 %). Además probarlo jugando.
- Modo libre: también con animales y tráfico (según la dificultad), sin reloj.

**Pendiente 13 — fase C, cómo quedó (tráfico, 2026-11-10)**
- Criterio (conversado con el usuario): en este juego el tráfico es **escaso pero con intención**, no un flujo
  urbano. Se generan "encuentros" cerca de la mototaxi, como los animales, y cada vehículo plantea una
  decisión: ir detrás o adelantar.
- `RoadTraffic` (`project/scripts/road_traffic.gd`), lo crea `Main` al empezar (también en el Modo libre).
  Cantidad = `Difficulty` "traffic" (Fácil 0.4, Normal 1, Difícil 1.7; `--trafico=F` la fuerza, 0 = ninguno):
  hasta `round(3 × cantidad)` vehículos a la vez (1 / 3 / 5). Nuevo `Difficulty` "oncoming" = parte que viene
  **de frente** (0.1 / 0.35 / 0.5): sin ellos adelantar no costaría nada.
- **Dónde**: un lugar posible cada 25 m de vía; más en avenidas y calles del pueblo, poco en carreteras, casi
  nada en trochas (`ROAD_WEIGHT`). Aparecen 90–220 m adelante, nunca a < 40 m de la recogida o el destino ni
  a < 50 m de otro; se quitan a > 270 m (o > 110 m detrás) o si quedan atascados 25 s lejos de la mototaxi.
- **Tipos** (`TYPES`, `KIND_TYPES` por tipo de vía, `REGION_BIAS` por región):
  - Otras mototaxis (modelos del garaje, distinto del que usa el jugador), 20–28 km/h; abundan en el pueblo
    y en la selva.
  - Combi (hecha por código, `make_combi`: blanca con franja de color, letrero de ruta, parrilla),
    24–34 km/h; **para 3–6 s en los paraderos** (landmarks `paradero`).
  - Camioneta (Quaternius, CC0), 28–38 km/h. Camión (Quaternius, CC0), 16–24 km/h, **sube muy lento** las
    cuestas; más en la sierra. Modelos en `project/assets/traffic/` con su `SOURCE.md`; en Créditos. No hay
    combi CC0 en Poly Pizza (solo CC-BY), por eso se hizo por código.
- **Manejo**: `AnimatableBody3D` cinemático que sigue el trazo de la vía por su **carril derecho** (¼ del
  ancho, sin salirse del borde), con la altura de `get_height` e inclinado con la pendiente. Frena con ~1.1 s
  de distancia ante lo que tenga delante en su carril (la mototaxi, otro vehículo, animales): no embiste a
  la mototaxi parada. Ante un obstáculo fijo se corre lo mínimo hacia el lado libre (mira 30 m adelante) y
  frena si todavía no alcanzó a correrse. Al final de una vía sigue por otra que pase por ese punto (las
  trochas casi solo para mototaxis y camionetas); si no hay, da media vuelta.
- **Golpe**: si la mototaxi lo toca a > 8 km/h de diferencia, daño `(km/h − 8) ×` factor (mototaxi 0.45,
  camioneta 0.7, combi 0.8, camión 1.0; a 35 km/h contra una camioneta ≈ 19), razón `"vehiculo"`: el
  pasajero se enoja más que por un golpe normal, con frase ("¡Casi nos matamos! ¡Fíjese en los carros!"…).
  1.2 s de gracia y se apaga el "choque" de la física en ese golpe (no cuenta doble). El chofer se detiene
  2.5 s. Además el cuerpo tiene colisión: la mototaxi no lo atraviesa.
- **Costo**: ~1.7 ms por paso de física sin ventana (con la física de la mototaxi).
- Pruebas: `tests/test_trafico.gd [-- semilla]` (aparecen, de frente y en el mismo sentido, tope, sobre la
  vía, carril derecho, pegados al suelo, avanzan, frenan detrás de la mototaxi sin dañarla, golpe y ánimo,
  gracia, esquivan 5 obstáculos fijos sin atravesarlos, se quitan, densidad 0). Pasa en el mapa guardado.
  Capturas: `tests/capture_trafico.gd -- --editor` (con ventana) → `output/trafico/` (cada tipo de frente y
  vista de juego desde atrás).
- Pendiente para la fase D: el piloto automático (`test_drive_routes`) no ve el tráfico (no usa `Main`);
  la bocina todavía no hace nada con los vehículos.

**Pendiente 13 — fase B, cómo quedó (animales, 2026-11-08)**
- `RoadAnimals` (`project/scripts/road_animals.gd`), lo crea `Main` al empezar (también en el Modo libre).
  Cantidad = `Difficulty` "animals" (Fácil 0.5, Normal 1, Difícil 1.8; `--animales=F` la fuerza, 0 = ninguno);
  hasta `ceil(6 × cantidad)` grupos a la vez.
- **Modelos** (el usuario prefirió importados, comunes en Perú y livianos): 7 animales animados de Quaternius
  (CC0), de Poly Pizza, en `project/assets/animals/` con su `SOURCE.md`; en Créditos. 800–3600 triángulos.
  - Costa: perro, gallina, algún burro. Sierra: alpaca, oveja (rebaños), burro, vaca. Selva: gallina,
    chancho, vaca, algún perro. La región es la de `get_biome` en ese punto.
  - Se descartó la llama de Quaternius: solo trae "quieta" y "salto".
- **Dónde**: un lugar posible cada 20 m de vía (no en puentes); más en trochas y calles, pocos en
  carreteras. Aparecen adelante de la mototaxi a 55–150 m, nunca a < 35 m de la recogida o el destino, y se
  quitan a > 210 m (o > 90 m detrás). Los modelos se reusan desde un pozo (no se instancian cada vez).
- **Comportamiento**:
  - Grupos que **pastan** al borde y **cruzan** cuando la mototaxi llega a 22–48 m (perros y gallinas
    corriendo). Solo pastan en un costado con suelo parejo, no en la ladera de una vía cortada en el
    cerro. Si el otro costado es ladera, se meten a la vía y luego vuelven.
  - Grupos que **caminan por la vía** siguiendo su trazo (ovejas, alpacas, vacas, burros; si ningún
    costado sirve, todos). Ocupan el carril hasta que la mototaxi se acerca a < 15 km/h o toca la bocina;
    ahí se apartan a un costado parejo (o a la berma). Es lo que más tiempo hace perder.
  - Si la mototaxi pasa rozando a > 20 km/h, huyen corriendo (sin subir laderas).
- **Bocina** nueva: H / B del mando (`Mototaxi.honk`, señal `honked`, sonido generado por código); aparta a
  los que estén a < 35 m. En Controles.
- **Golpe** por cercanía, sin física (una gallina no frena en seco a la mototaxi): daño `(km/h − 6) ×` factor
  de la especie (a 30 km/h: gallina ≈ 2, oveja ≈ 8, vaca ≈ 15), razón `"animal"`. El pasajero se enoja más que
  por un golpe normal, con una frase ("¡Cuidado con el animal!"…). Los grandes frenan la mototaxi (hasta
  35 %). Cada animal golpea una vez; 1.2 s de gracia entre golpes; el animal huye.
- **Costo**: 1–2 ms por paso de física sin ventana (con la física de la mototaxi); con ventana, 144 FPS con
  y sin animales (tope de la pantalla).
- Pruebas: `tests/test_animales.gd [-- semilla región]` (lugares, región, no en laderas, lejos del
  destino, golpe y ánimo, gracia, bocina, se quitan y se reusan, densidad 0). Pasa en el mapa guardado,
  `42 sierra` y `7 costa`. Capturas: `tests/capture_animales.gd -- --seed=42 --region=sierra` (con ventana) →
  `output/animales/` (una por especie y vista de juego), y mide FPS.
- El piloto automático (`test_drive_routes`) no los ve: no usa `Main`.

**Pendiente 10 — plan "Red vial, paradas y ambientación" (planteado 2026-11-06)**

Pedido: paradas que no sean siempre las mismas 3 con los mismos nombres, nombres propios de cada región,
paradas con más ambientación que un cartel (que no se vea desértico) y una red vial menos de "circuito de
carreras": más de un camino en tierra llana (en la montaña es lógico que haya uno solo).

*Diagnóstico (cómo está hecho)*
- Vías: C++ `RoadNetwork::_generate_hierarchy` (`src/road_network.cpp`, autor josep-castro). Pone
  `town_count` = 4 pueblos, uno por sector angular alrededor del centro; los une con un árbol de enlaces más
  cortos + **una sola** conexión extra (la que más rodeo ahorra) → casi siempre un solo camino; a cada
  pueblo le agrega a lo mucho una calle corta (`kind` 3). Las carreteras son `kind` 1.
- La vía se traza con A* sobre el relieve base (evita pendiente y agua) **antes** de la erosión, y luego el
  terreno se aplana a lo largo de las vías (`src/terrain_mesh.cpp`, `limit_network_grade`, `road_weight`):
  el terreno se adapta a las vías, no al revés. Agregar caminos = agregar tramos a esa lista.
- Lo delicado son los **cruces**: un camino nuevo debe terminar en un punto exacto de otro (cortar la vía
  ahí) para que el aplanado de la unión (`is_node`/`uses`) y el GPS (`RoadRouter`, que une puntos iguales
  a 10 cm) lo vean como cruce.
- La forma cambia con la semilla; el escenario guardado (`terrain_demo.tscn`) usa la semilla 2.
- Paradas (`TerrainWorld._build_landmarks`): centros de pueblo + puntos cada 60 m sobre las vías + rasgos
  (picos, confluencias, costa; en el mapa guardado no se detecta ninguno).

*Fases (en este orden: la 2 es la base de la 3 y la 4)*
1. ✅ **Nombres por región** (2026-11-06, GDScript). `StopNames` (`project/scripts/stop_names.gd`): banco de
   18 nombres propios por región + plantillas por tipo (plaza, mercado, paradero, colegio, posta, grifo,
   chacra/fundo, huaca/comunidad/embarcadero, mirador, confluencia/puente, playa). Cada landmark trae
   `region`, `kind` y `label`; los pueblos son plaza o mercado, los rasgos mirador/confluencia/playa y
   paradas de vía separadas ≥ 220 m reciben un tipo al azar ("via" = sin nombre). Sale de la semilla del
   mundo (mismo mapa = mismos nombres), sin repetir. Cartel para cada parada con nombre (color por tipo, al
   costado de la vía, nunca sobre la calzada). En el mapa guardado: 22 de 131 paradas con nombre.
   Prueba: `tests/test_paradas.gd`.
2. ✅ **Red vial más residencial** (2026-11-06, C++ `RoadNetwork::_grow_network`, hecho en `juego`). Resumen
   abajo en "Fase 2 — cómo quedó"; el plan original era:
   - 2a. Más conexiones entre pueblos: toda conexión que ahorre mucho rodeo (por ejemplo, ruta por vías
     > 1.4 × la distancia directa), si A* la encuentra bajo la pendiente máxima; en la montaña no
     se construye sola → "una sola vía en la sierra" sale del relieve. Parámetro tipo `extra_links`.
   - 2b. Cuadrícula de calles en cada pueblo en terreno plano (3×3 o 4×4 cuadras de `block_size` 32 m),
     recortada por pendiente y agua → caminos alternativos dentro del barrio.
   - 2c. Trochas rurales (`kind` 0, más angostas, textura de tierra) de la carretera a chacras/caseríos;
     a veces se vuelven a unir con otra vía (vueltas); pueden quedar sin salida.
   - 2d. Cruces: cortar la vía existente en el punto de unión (riesgo técnico principal).
   - Validar: `roads_test`, `test_drive_routes -- 8 editor`, alcanzabilidad (`is_reachable`), tiempo de
     generación, cruces bien aplanados y con textura, FPS.
3. ✅ **Paradas sobre la red nueva** (2026-11-06, GDScript). `TerrainWorld._road_sites` lee la red (puntos
   compartidos a 10 cm = cruces; extremo de trocha que no comparte = sin salida) y marca `site` en:
   `mercado` (cruce de calles a 40–80 m de la plaza), `colegio` y `posta` (cruces de calles más afuera,
   separados ≥ 60 m), `cruce` (carretera/avenida que se une con otra vía fuera del pueblo, cada ≥ 300 m),
   `trocha` (final sin salida), `ribera` (carretera a ≤ 15 m de un cauce, cada ≥ 400 m) y `carretera`
   (lejos de pueblos y cruces, cada ≥ 900 m). `StopNames` convierte el sitio en tipo: mercado, colegio,
   posta, paradero, chacra (o huaca/comunidad en costa/sierra, 30%), playa/puente/embarcadero según la
   región, grifo. El centro del pueblo es la plaza (con mercado a una cuadra). Solo las paradas sin sitio
   se sortean (paradero, chacra o grifo). Los carteles de cruces de cuadras prueban también en diagonal.
   Mapa guardado: 46 de 259 paradas con nombre (antes 22 de 131): 4 plazas, 4 mercados, 4 colegios,
   4 postas, 12 paraderos, 13 chacras, 3 grifos, 1 embarcadero. `tests/test_paradas.gd` comprueba cada
   tipo en su lugar.
4. 🟡 **Ambientación: casas y objetos por región y por tipo de parada.** Viviendas ✅ (2026-11-08, ver
   "Fase 4 — viviendas, cómo quedó"); falta la ambientación por tipo de parada (bancas de la plaza, puestos
   del mercado, techito del paradero, surtidor del grifo, muelle...). Ver "Fase 4 — cómo pedirla" abajo.
5. ✅ **Obstáculos de animales** (pendiente 5), 2026-11-08: ver "Pendiente 13 — fase B, cómo quedó".

*Fase 4 — cómo pedirla* (pedir en sesión nueva: "haz la fase 4 del pendiente 10", en la rama `juego`)
- **Objetivo.** Que los pueblos y paradas no se vean desérticos: las cuadras de la fase 2 se llenan de
  casas y cada parada con nombre tiene algo propio alrededor del cartel.
- **Casas por región** (según `get_biome` en ese punto):
  - Costa: adobe o quincha, techo plano, colores claros.
  - Sierra: adobe con techo de teja a dos aguas.
  - Selva: madera con calamina, o palafitos cerca del agua.
  - En zonas mixtas se toma la región que domina.
- **Dónde van.**
  - Casas en fila a los dos lados de las calles (`kind` 3), frente a la vía y a unos metros del borde.
  - Solo donde el suelo es firme (`get_offroad_amount` alto), con poca pendiente y sin agua.
  - Nunca sobre la calzada ni tapando un cruce.
  - Menos casas, más separadas, en avenidas y carreteras cerca del pueblo; casi nada en trochas (solo la
    casa de la chacra al final).
- **Ambientación por tipo de parada** (los tipos de `StopNames` y los `site` de `TerrainWorld._road_sites`):
  - Plaza: espacio abierto, bancas, árboles.
  - Mercado: puestos con toldos.
  - Paradero: techito.
  - Colegio y posta: edificio más grande con muro o patio.
  - Grifo: surtidor con techo.
  - Chacra: casa pequeña y cerco.
  - Embarcadero / playa / puente: muelle o bote, según la región.
- **Cómo hacerlo** (lo que ya funciona en la vegetación):
  - Muchas copias de pocos modelos con MultiMesh, como `TerrainVegetation`.
  - Versiones simples o impostores de lejos (`VegetationImpostors`).
  - Colisión solo cerca de la mototaxi, como `TreeColliders`/`NearVegetation`.
  - Quitar la vegetación que quede dentro de una casa.
  - Todo sale de la semilla del mundo: mismo mapa, mismas casas.
- **Modelos.** CC0 (Quaternius, Kenney u otros), o casas armadas por código como las plantas de
  `VegetationAssets` (cajas y techos simples, con color por vértice). Lo primero es preguntar cuál
  prefiere el usuario.
- **Estilo.** El terreno busca ser realista pero optimizado; las casas deben ir con ese estilo y no con el
  de las pistas actuales, que se ven rústicas (ver "Puntos a mejorar para el equipo de gráficos", punto 2).
- **Presupuesto.** Hoy 150–165 FPS; la carga del mapa sube como mucho ~0.5 s.
- **Validar.**
  - Una prueba nueva tipo `tests/test_ambientacion.gd`:
    - ninguna casa sobre la calzada ni en agua;
    - cada parada con nombre tiene su objeto;
    - mismas casas con la misma semilla.
  - `test_drive_routes -- 8 editor` sigue 8/8 (las casas no bloquean rutas).
  - `test_paradas`, `hierarchy_test`.
  - Capturas de pueblos en costa, sierra y selva (como `tests/capture_red_vial.gd`).
  - FPS.

*Fase 4 — viviendas, cómo quedó (2026-11-08)*
- `TerrainHouses` (`project/scripts/terrain_houses.gd`), lo arma `TerrainWorld._build_houses` después de
  las paradas y antes de los obstáculos y la vegetación. Modelos importados de Poly Pizza (el usuario
  prefirió importar): 11 GLB en `project/assets/houses/` con autor y licencia en su `SOURCE.md`
  (Quaternius, Kenney, CreativeTrio CC0; Jarlan Perez y Poly by Google CC-BY 3.0, en Créditos).
  - Costa: casas de dos pisos de colores con techo casi plano (Kenney) y casita blanca de techo rojo.
  - Sierra: casas de muros claros y techo de teja (Quaternius, CreativeTrio).
  - Selva: chozas y cabañas de madera, una sobre pilotes (Quaternius, Poly by Google).
- Dónde: fila casi continua a los dos lados de las calles del pueblo (`kind` 3); cada 6–22 m en avenidas
  y carreteras a < 260 m de un pueblo; una suelta cada 140–420 m de carretera o 90–260 m de trocha en el
  campo; la casa de la chacra al final de las trochas sin salida. Frente (puerta) hacia la vía, a 1.5 m
  del borde. Mapa guardado: ~460–490 casas (selva y costa; ese mapa no tiene sierra).
- Reglas: nada sobre una vía (`get_offroad_amount`), a < 3 m de un cauce, a < 4 m de una parada o
  a < 2.5 m de un cartel, ni cruzada con otra casa; solo en zona transitable con desnivel ≤ 1.4 m; la
  región del modelo es la del lugar. El piso va en lo más alto del suelo y un zócalo de piedra cubre el
  desnivel (no flota ni se entierra).
- Funcional: cada casa tiene una caja de colisión (chocarla a 36 km/h quita ~20 de vida); los árboles que
  caerían adentro se quitan (`ChunkMesh.vegetation_blockers` → `TerrainVegetation`); el tronco caído de
  los obstáculos no se mete en una casa.
- Dibujo: MultiMesh por modelo y baldosa de 256 m, hasta 900 m. Construirlas: ~0.2–0.5 s. FPS en la
  calle de un pueblo: 144 con casas, 138 sin ellas (sin diferencia medible).
- Pruebas: `tests/test_viviendas.gd [-- semilla región]`; capturas `tests/capture_viviendas.gd`
  (con ventana; también mide FPS) → `output/casas/`; foto de cada modelo `tests/capture_casas_modelos.gd`.
- Para el equipo de gráficos: los modelos son low poly de estilo caricatura; se pueden cambiar en
  `TerrainHouses.MODELS` (archivo, región, alto real en m y giro para que la puerta mire a +Z).
- Nota: `test_terrain_world` falla en "pendiente máxima en vías 0.74" también sin estos cambios (ya
  fallaba en el commit 21a726e).

*Fase 5 — cómo pedirla* (pedir en sesión nueva: "haz la fase 5 del pendiente 10", en `juego`)
- **Objetivo.** Animales que cruzan o caminan por la vía, estilo Mario Kart: obstáculos que hay que
  esquivar, no enemigos.
- **Qué animales y dónde** (lugares que ya existen gracias a las fases 2–4):
  - Costa: perros y gallinas en calles del pueblo.
  - Sierra: llamas, alpacas y ovejas en trochas y carreteras de la sierra (rebaño que cruza).
  - Selva: chanchos y gallinas cerca de casas y chacras.
  - Más animales en pueblos y trochas; pocos en carreteras abiertas.
- **Comportamiento.**
  - Aparecen solo cerca de la mototaxi (a unos 60–150 m, fuera de cámara si se puede) y desaparecen
    lejos, para no gastar FPS.
  - Cruzan la vía de un lado al otro o caminan un rato por ella; se apartan o se asustan si la mototaxi
    pita o se acerca despacio.
  - No se ponen sobre el punto de recogida ni sobre el destino.
- **Al chocar.**
  - Daño a la mototaxi con `Mototaxi.apply_damage(cantidad, "animal")`.
  - Enojo del pasajero: baja `_comfort` en `RaceManager`, como los golpes; frase del pasajero.
  - El animal huye; nada gráfico.
  - Que no sea injusto: aviso visual o sonido antes, y un tiempo de gracia entre golpes.
- **Modelos.** Animales CC0 de bajo detalle (Quaternius tiene "Farm Animals" / "Animal Pack"); revisar
  licencia y anotarla en Créditos (`loading_screen.gd`) y en el `SOURCE.md` de la carpeta del modelo.
- **Opciones.**
  - Cuántos animales hay (ninguno / pocos / muchos), en Opciones o al elegir el escenario.
  - En el Modo libre también aparecen.
- **Validar.**
  - Una prueba sin ventana: aparecen según la región, nunca fuera de la vía o del pueblo, chocar resta
    vida y ánimo.
  - El piloto automático sigue completando viajes con los animales desactivados.
  - FPS con el máximo de animales.
- Ideas relacionadas para después: pendiente 6 (piedras de huaico, baches, combis lentas) y la bocina
  para espantar animales como mejora del garaje.

*Decisiones (2026-11-06)*: la fase 2 se hizo en `juego` (coordinar con josep-castro: toca
`road_network.cpp`); el escenario guardado puede cambiar. No hizo falta regenerar `terrain_demo.tscn`: la
escena guarda solo configuración + suelo y el juego rehace las vías con la DLL al arrancar.

*Fase 2 — cómo quedó*
- **Inserción con cruces exactos (2d).** Todo trazo nuevo pasa por `insert`: se corta donde toca una vía
  (distancia < semianchos + 2.5 m) y cada tramo libre empieza/termina **en un punto exacto** de la vía que
  toca (no hace falta partir la vía: un punto compartido a mitad de vía ya es nodo para
  `limit_network_grade` y para `RoadRouter`). También descarta tramos paralelos a la misma vía.
- **2a. Enlaces extra** (`extra_links` = 4, `detour_ratio` = 1.4): candidatos pueblo–pueblo (carretera),
  pueblo–carretera de paso y "travesaños" entre dos carreteras a 150–700 m que por la red quedan a
  > 2.5× (avenida, `kind` 2). Se rechaza el trazo si es > 1.5× la distancia directa, con pendiente > 0.18
  en 40 m (`extra_link_grade`) o si va pegado (< 60 m) a otra vía en más del 45%; separados ≥ 400 m.
  En la semilla 2 el enlace oeste–noreste daría 3.9 km de vueltas por la sierra y no se construye.
- **2b. Cuadras** (`town_blocks` = 4 → 4×4 cuadras de `block_size`): cuadrícula alineada con la carretera
  que sale del pueblo; cada cuadra se valida (seca, pendiente ≤ `road_max_grade`, sin ladera de costado).
- **2c. Trochas** (`kind` 0, `trail_width` 4.5 m, color tierra): `farm_tracks` = −1 → una cada ~450 m de
  carretera (máx. 24), lejos de los pueblos, a una chacra a 90–260 m sin salida, o con 40%
  (`track_loop_chance`) de vuelta a otra vía que por la red queda lejos. Pendiente ≤ 0.24 en 30 m.
- Al final se quitan las vías que quedaron sin unir a las carreteras.
- `grow_network = false` (en `ChunkMesh`) deja la red de antes. Los parámetros están en `ChunkMesh`.
  `DEBUG_ROADS=1` imprime los enlaces evaluados.
- A* con ventana (`_find_path(..., window)`): busca en un cuadrado de la misma grilla alrededor del inicio
  y la meta; las carreteras no cambian.
- **Mapa guardado (semilla 2)**: antes 4 carreteras + 2 calles; ahora 4 carreteras, 4 avenidas, 89
  tramos de calle y 24 trochas. Red vial 0.34 → 0.6 s; reconstrucción total 2.0 → 2.4 s. Pendiente
  máxima en vías 0.49 → 0.18; 0 de 2437 tramos sobre 0.35; 249 paradas (antes 131), todas en una zona
  transitable. Capturas: `tests/capture_red_vial.gd` → `output/red_vial/`.

**Pendiente 7 — una sola carrera + Modo libre (decidido 2026-11-06, hecho 2026-11-06)**

Problema: el menú "Continuar / Nueva partida" es de juego con historia (varias líneas de tiempo), pero las
reglas son de roguelite (ahorros que se pierden al perder, compras que se quedan). "Nueva partida" solo
servía para borrar la guardada; tener varias líneas de tiempo rompería las compras globales.

- **Una sola carrera.** Se quita "Nueva partida". Menú: Jugar/Continuar · Modo libre · Garaje · Opciones ·
  Controles · Créditos · Salir. Sin partida guardada, "Jugar" abre la configuración del mundo (como hoy);
  con partida, "Continuar · Día N".
- **Escenario dentro de la partida.** Al terminar el día, junto a "Garaje", un botón para cambiar el
  escenario (región, terreno/semilla, calidad): se regenera el mapa y el día siguiente empieza ahí. En la
  pausa no se cambia a mitad del día; ahí la configuración elegida se aplica al **reiniciar** ("Reiniciar
  partida" = abandonar y empezar de cero, desde el día 1 y sin ahorros, con confirmación).
- **Modo libre.** Explorar escenarios (el otro punto fuerte del juego, el terreno): sin cuota, sin dinero, no
  guarda ni toca la carrera; cualquier terreno, región o semilla.
- **Se mantiene** lo hecho el 2026-11-06 (ahorros por partida, compras permanentes, mototaxi en uso, cuota
  fija, garaje en el menú y al terminar el día, `carrera_pruebas.cfg` para las pruebas).
- **Decidido:** (a) al terminar el día se puede cambiar todo (terreno guardado o nuevo con semilla, región,
  calidad); (b) Modo libre solo con las mototaxis compradas (como el modo práctica de Geometry Dash: sirve
  para explorar, pero lo que se desbloquea se gana en la carrera), sin pasajeros, reloj, dinero ni récord;
  si se destroza, se sale del mapa o queda atrapada, reaparece; (c) tras perder, "Reintentar" sigue en el
  mismo mapa y al lado está "Cambiar escenario" (día 1 en otro).
- **Cómo funciona:** el selector de escenario es `ScenarioPicker` (menú) y `ScenarioPanel` (fin del día,
  fin de partida y pausa). Si el escenario cambia, Main deja lo elegido en `CareerSave.launch` (solo en
  memoria) y recarga la escena, que genera el mapa nuevo sin pasar por la portada; si es el mismo, sigue
  sin regenerar. Al terminar el día, la partida guardada pasa a ese escenario (sin posición: se empieza en
  la zona de la región). En la pausa, "Reiniciar partida" abre el panel (avisa que se pierden los ahorros);
  en Modo libre la pausa ofrece "Cambiar escenario" y "Volver al inicio" (sin "Guardar"). Con partida
  guardada, "Jugar" no aparece (solo "Continuar · Día N"). `--libre` entra directo al Modo libre.

**Opciones para darle sentido al dinero** (en GTA el taxi solo suma dinero; aquí el juego necesita una meta)
1. **Cuota del día (alquiler de la mototaxi).** La partida es una jornada con reloj (p. ej. 6–8 min). Al final
   hay que pagar la cuota al dueño; si no alcanza, fin de partida. Cada día la cuota sube. Da un final claro y
   presión de tiempo aunque la mototaxi esté sana.
2. **Gastos que obligan a ganar.** Gasolina que se acaba (se recarga pagando en grifos del mapa) y
   reparaciones pagadas (taller o "R" con costo). El dinero se vuelve vida: si te quedas sin plata y sin
   gasolina, pierdes.
3. **Progreso entre partidas.** Lo ganado se guarda y sirve para comprar las mototaxis del garaje y mejoras
   (turbo, suspensión, blindaje, bocina para espantar animales). Da motivo para jugar otra vez.
4. **Deuda de la mototaxi.** Empiezas debiendo S/ X; cada jornada pagas una cuota; saldarla es "ganar" el
   juego (modo historia corto).

Elegido: **1 + 3** (2026-11-04). Las reparaciones pagadas (opción 2) quedan como idea si hace falta más tensión.

**Cómo funciona el dinero ahora**
- **Pago sin propina.** Tarifa = base + por km de la ruta. A tiempo y sin golpes paga completo; los golpes y
  vuelcos rebajan hasta 60 % (`rough_pay_min`). Si se acaba el tiempo, el pasajero sigue a bordo pero
  *tarde*: paga desde 70 % (`late_pay_start`) bajando hasta nada al final del margen (`late_grace`, 60 % del
  tiempo límite, mínimo 15 s); pasado el margen se baja sin pagar. Se redondea a 10 céntimos.
- **Jornada con cuota.** Cada día dura 6 min (`day_length`); la cuota es fija, S/ 10 por día
  (`quota_per_day = 0`: lo que cuenta es lo ganado ese día). Si el reloj llega a 0 con pasajero a bordo, se
  termina ese viaje. Con la cuota juntada, lo que sobra va a los ahorros de la partida y sigue el día
  siguiente (mototaxi reparada); si no, fin de partida. Ya no se pierde por pasajeros perdidos
  (`max_failures = 0`); siguen el fin por vida, borde y atrapado.
- **Ahorros por partida, compras para siempre.** `user://carrera.cfg` tiene dos niveles: la carrera
  (mototaxis compradas, la que está en uso y mejor jornada; se conserva siempre) y la partida (estado
  guardado y sus ahorros). Perder o "Reiniciar partida" (pausa, pide confirmar) borran la partida y sus
  ahorros; lo comprado se queda (ya no hay "Nueva partida": ver Pendiente 7). Objetivo a largo
  plazo, sin anunciarlo: conseguir todas las mototaxis. Las pruebas (`-s`) usan `carrera_pruebas.cfg`.
- **Garaje con precios.** Se empieza con Neon Shadow; las demás cuestan S/ 30–85 (`price` en
  `VehicleCatalog`). El garaje es una entrada propia del menú principal y también se abre desde el resumen
  de cada día cumplido: comprar (queda en uso) o "Usar esta". "Continuar", "Jugar", el Modo libre y el día
  siguiente usan la mototaxi en uso; "Jugar" solo configura el terreno.
- **Reloj acelerado.** Los 6 min reales van de 07:00 a 19:00 en el reloj del juego (`day_start_hour`,
  `day_end_hour`; 1 s real = 2 min). El HUD muestra la hora y la de cierre. La luz del sol todavía no sigue la
  hora (queda para la parte gráfica).
- **Guardar y cargar.** "Guardar partida" en la pausa y autoguardado al completar cada día
  (`CareerSave.save_game`): mundo elegido, día, hora, lo ganado, vida y posición. "Continuar · Día N" en el
  menú principal regenera ese mundo y sigue; el viaje en curso no se guarda (empieza con pasajero nuevo).

---

## Integración terreno de CG + juego (2026-10-19)

**Hecho**
- Merge de `origin/main` en `juego` (sin commit aún: queda preparado en staging). Conflictos resueltos:
  C++ y DLL tomados de `main`; `project.godot` con el nombre de `main` y `run/main_scene = main.tscn`;
  el `TerrainWorld` de `main` (basado en `TerrainField`, visor auxiliar `world_demo.tscn`) se renombró a
  `TerrainFieldWorld` (`scripts/terrain_field_world.gd`); `TerrainWorld` es el del juego.
- `TerrainWorld` usa `chunk_mesh.gd` de CG como generador (T0 + erosión al 10% de los pasos por defecto,
  `erosion_scale`), y añade: colisión `HeightMapShape3D` + colisión de puentes, tableros de puente en las
  alturas del juego, landmarks sobre vías/pueblos, mapa de transitabilidad (`get_reach_id`, `is_reachable`)
  y `find_route` que evita pendientes > `max_drive_slope`. Mapa por defecto: 512 celdas × 1.5 m = 768 m.
- C++ (cambios propios para el juego; con valores por defecto CG queda igual salvo la diagonal):
  - `terrain_mesh.cpp`: `road_max_grade` limita la pendiente de las vías (corte/relleno, cruces y vías
    superpuestas unidas a la misma altura). El juego usa 0.25; `chunk_mesh.gd` tiene 0 (sin límite).
  - `terrain_mesh.cpp`: la malla usa la diagonal (10)-(01), igual que `HeightMapShape3D` (antes la malla
    visual y la colisión diferían hasta ~3 m en celdas empinadas).
  - `road_network.cpp`: nuevo `find_drivable_path(heights, samples, cell, a, b, max_slope)`.
- Mototaxi: "marcha corta" (`low_speed_boost` 1.8 hasta 30 km/h) y al rodar hacia atrás con W ya no corta
  el motor. Sube 0.45 (24°) desde parada y ~0.65 (33°) lanzada; antes se quedaba en 0.35 (19°).
- `RaceManager` solo elige pasajeros/destinos alcanzables manejando; la mototaxi aparece en la zona
  transitable más grande. El sol de `main.tscn` se alinea con el del shader de CG.

**Mediciones** (`tests/diag_terrain.gd`, `tests/diag_climb.gd`, `tests/test_drive_routes.gd`)

| | Terreno anterior (`juego`) | Terreno CG (erosión 10%, vías limitadas) |
|---|---|---|
| Pendiente del mapa p99 | 6.33 (~81°) | 2.68 (1.89 con erosión completa) |
| Rutas A* con tramos > 0.35 | 6.4% (máx. 4.34) | 0.1% → ahora ≤ ~0.43 con `find_drivable_path` |
| Vías con pendiente > 0.35 | — | 0% (máx. ~0.27) |
| Landmarks en una zona transitable | — | 100% |
| Viajes con piloto automático | — | semilla 67: 8/8; semilla 2026: 5/6 |

**Pendiente de esta tarea**
- Semilla 2026, cerca de (104, −208): cresta angosta al borde de una carretera (pendiente local ~0.7)
  donde el piloto automático se atasca/vuelca a veces. Ideas: suavizar el borde de la vía (`road_fade`
  más ancho o limitar la pendiente lateral del corte en `terrain_mesh.cpp`), o que la ruta prefiera vías.
- La ruta recomendada va campo traviesa; para S12 conviene que siga las vías (red vial ya disponible en
  `get_roads()`).
- Carga ~16–22 s (erosión al 10% + texturas). La caché de texturas de CG (`textures/_cache`) no se
  puede leer (también en `main`) y se reconstruye cada vez (~8 s): avisar a CG.
- `textures_test` de CG falla también en `main` puro ("La elevación del sol debe llegar al shader").
- La DLL se compiló con MSVC (`scons platform=windows target=template_debug arch=x86_64 api_version=4.7`);
  CG usa `tools/build.ps1` (LLVM-MinGW). Cualquiera sirve, pero recompilar tras cambiar `src/`.

## El juego usa el escenario del editor (2026-10-21)

Antes `main.tscn` generaba su propio mapa con los valores por defecto de `chunk_mesh.gd` (semilla 67,
512 × 1.5 m = 768 m, sierra 130 + 85 m, 16 parches) e ignoraba lo calibrado en `terrain_demo.tscn`.
Ahora `TerrainWorld.use_editor_scene = true` (en `main.tscn`) copia el nodo `Terrain` de
`editor_scene` (`res://terrain_demo.tscn`): todos sus parámetros, el sol, la nieve y el suelo ya
erosionado (`ground_bytes`). Solo rehace ríos y vías encima (`chunk_mesh.rebuild_saved_ground()`),
con el `road_max_grade` del juego.

**Cómo cambiar el escenario del juego (costa, sierra, selva)**
1. Abrir `terrain_demo.tscn`, seleccionar `Terrain` y ajustar el Inspector
   (grupo "S11 CG-B - regiones del T0": `region_patches`, `transition_width`, `coast_*`, `mountain_*`,
   `jungle_*`; `noise_seed` cambia el reparto de regiones).
2. Botón "1. Generar terreno nuevo (T0)" y luego "2. Aplicar erosión al terreno actual".
3. Guardar con Ctrl+S. El juego toma ese terreno en la siguiente ejecución, sin más pasos.
   Los parámetros de terreno del nodo `TerrainWorld` del juego (grid, semilla, erosión) ya no se usan
   mientras `use_editor_scene` esté activo; `generator_overrides` sí se aplica encima.

**Mediciones con el terreno guardado hoy** (semilla 2, 1024 × 3 m = 3072 m, `tests/test_editor_scene.gd`)
- Mapa: costa 23%, sierra 21%, selva 55%. Landmarks: 41 costa, 6 sierra, 69 selva; los 116 en una zona transitable.
- Vías: 4 de 2186 tramos sobre 0.35 (máx. 0.49, en (166, 1423) y (1055, −723)).
- Piloto automático (`test_drive_routes.gd -- 8 editor`): 7/8; se atascó en (−324, 819) con suelo a 0.68.
- `terrain_demo.tscn` ya no guarda la malla, el agua ni los puentes (pesaba 113 MB): solo la
  configuración (`terrain_snapshot`) y el suelo (`ground_bytes`), ~6 MB. Al abrir la escena o
  arrancar el juego se rehacen en ~2 s. El juego carga en ~2 s (antes ~10 s).
- Se quitó el transform del nodo `Terrain` (estaba rotado ~9° y a 4 km del origen: no se veía en 3D).

## Puntos a mejorar para el equipo de gráficos (anotados 2026-11-06)

Encontrados mientras se hacía la red vial en `juego`. El objetivo teórico principal es un terreno
generado de forma optimizada pero realista; estos puntos desentonan con eso.

1. **Nodo `Terrain` rotado en `terrain_demo.tscn`.** Tiene un `transform` girado ~31° e inclinado ~3.5°
   (ya estaba en la versión del 2026-10-21; parece un movimiento accidental en el editor). Por eso falla
   `textures_test` ("La elevacion del sol debe llegar al shader"): el sol se pasa al shader en el espacio
   del terreno y la inclinación lo desvía. Arreglo probable: dejar el transform en identidad y volver a
   guardar la escena (el juego no usa ese transform; copia solo los parámetros y el suelo).
2. **Vías con aspecto rústico.** La calzada se pinta con el color de vértice de la malla (celdas de 3 m),
   así que las calles (6 m) y las trochas (4.5 m) se ven con bordes borrosos, y las trochas son un color
   tierra liso, sin textura. Ideas: máscara de vías en una textura de más resolución o malla propia de la
   calzada (cinta) con textura de asfalto/tierra, bordes y veredas en los pueblos.
3. **La sierra queda fuera del juego.** En el mapa guardado (semilla 2) ninguna vía entra a la sierra
   (21% del mapa): 0 de 249 paradas están en la sierra. Los pueblos se ubican por sector buscando suelo
   llano y las vías evitan la pendiente. En versiones anteriores la sierra además era difícil de manejar
   y muchos destinos no se alcanzaban. Ideas: asegurar al menos un pueblo en una meseta o valle de la
   sierra y una carretera con curvas de herradura (serpentinas) que suba con pendiente ≤ 0.16.
4. **Fin del mapa en el horizonte.** Más allá del borde se ve el "suelo" del cielo procedural (franja
   marrón oscura bajo el horizonte). Para las fotos del selector se igualó, solo en la captura, el color
   del suelo del cielo al del horizonte y se puso neblina; en el juego convendría algo así (o un
   horizonte lejano) para que el mapa no se vea como una maqueta.
5. **Pueblos sin edificios.** Las cuadras de los pueblos están hechas (fase 2), pero hoy son calles en
   medio de la vegetación; la fase 4 (jugabilidad) pondrá casas por región, y conviene que el estilo de
   esos modelos lo acuerde el equipo de gráficos.

## Computación Gráfica (rama `main`)

Todo lo del PDF de la semana 10 está hecho; el detalle de cada tarea está en `docs/s11_cgb.md` y `docs/s12_s14_cg.md`.

| Sem. | Tarea (CG-A / CG-B) | Estado |
|---|---|---|
| S11 | Heightfield C++, flow routing, erosión fluvial y térmica a una resolución | ✅ |
| S11 | T0 con gradiente costa–sierra–selva; mapas ρ y s₀ por región | ✅ |
| S12 | Bucle multiescala 256 → 512 → 1024, upsampling bicúbico, deposición | ✅ |
| S12 | Chunks 128×128, `HeightMapShape3D`, shader de splatting | ✅ |
| S13 | Retargeting por difusión, pantalla de carga, breaching (opcional) | ✅ |
| S13 | Ríos desde el drenaje en el shader, landmarks automáticos, caminos sobre terreno erosionado | ✅ |
| S14 | Figuras del pipeline y tabla de tiempos; niebla, cielo, agua | ✅ |

---

## Pruebas sin ventana

Desde la raíz del repo (ajustar la ruta del ejecutable de Godot 4.7):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path project -s res://tests/test_terrain_world.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path project -s res://tests/test_mototaxi.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path project -s res://tests/test_race.gd
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_passenger.gd
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_jornada.gd    # cuota, ahorros, garaje, mapa
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_dificultad.gd # dificultad de la partida
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_animales.gd   # animales [-- semilla región]
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_trafico.gd    # tráfico [-- semilla]
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_partida.gd    # guardar/cargar, reloj
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_escenario.gd  # cambiar escenario, Modo libre
Godot_v4.7.2-stable_win64_console.exe --headless --path project -s res://tests/test_destinos.gd   # viajes corto/medio/largo y su pago
Godot_v4.7.2-stable_win64_console.exe --headless --path project -s res://tests/test_paradas.gd    # nombres de paradas por región
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_obstaculos.gd   # obstáculos en las vías
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_viviendas.gd    # viviendas por región
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_vegetation.gd -- --editor
Godot_v4.7.2-stable_win64_console.exe --headless --path project -s res://tests/render_engine_audio.gd   # graba output/audio/mototaxi_demo.wav
```

Diagnósticos y prueba de manejo (más lentos):

```
... -s res://tests/diag_climb.gd                     # pendiente que sube la mototaxi
... -s res://tests/diag_terrain.gd -- game|full|demo|noerosion|nograde
... -s res://tests/test_drive_routes.gd -- 6 2026    # piloto automático: viajes y semilla
... -s res://tests/test_drive_routes.gd -- 8 editor  # piloto automático en el terreno de terrain_demo.tscn
... -s res://tests/test_editor_scene.gd              # el juego copia bien el escenario del editor
```

Si se agregó un script con `class_name` nuevo, correr antes una vez `--headless --path project --import`
para que Godot registre la clase.

## Registro

- **2026-11-01** — Merge de `main` en `juego` (se conservó el `terrain_demo.tscn` de `juego`). Vida, daño,
  vuelcos, fin de partida (vida, borde, atrapado, 3 pasajeros perdidos) y reinicio; ruta por vías dibujada
  en el mundo; tiempo con pendiente; ánimo, pasaje y propina; región elegida en el menú (`biome_bias`).
  `place_at` despierta el cuerpo (dormido ignoraba el cambio de posición). Pruebas: `tests/test_s13_juego.gd`,
  `tests/test_drive_routes.gd -- 8 editor` (8/8, 0 daño), capturas con `tests/capture_game_hud.gd`.

- **2026-10-18** — Ciclo de carrera S11 (J-B) completo: `RaceManager`, `GlowZone`, `RaceHUD` y `tests/test_race.gd`.
  Se devolvió `TerrainWorld` al origen en `main.tscn` (estaba desplazado a y≈96 y rotado, lo que rompía `get_height`).
- **2026-10-19** — Merge de `origin/main` en `juego` y juego sobre el terreno de CG; vías con pendiente
  limitada, transitabilidad, mototaxi con más fuerza en subidas (ver "Integración terreno de CG + juego").
- **2026-10-21** — El juego usa el terreno guardado en `terrain_demo.tscn` (`use_editor_scene`), en vez de
  generar uno con valores por defecto. Nueva prueba `tests/test_editor_scene.gd`.
- **2026-10-21** — `terrain_demo.tscn` guarda solo configuración + suelo (113 MB → 5.6 MB); la malla se
  rehace al abrir. `Terrain` vuelve al origen.
- **2026-11-02** — `juego` unido en `main` (avance rápido). Sonido de la mototaxi: motor monocilíndrico de
  4 tiempos sintetizado en tiempo real (pulsos de explosión → resonadores de silenciador y escape, variación
  entre ciclos), caja virtual de 4 marchas + reversa con embrague, rodadura y golpes de chapa en choques y
  vuelcos. Nodo `Audio` en `mototaxi.tscn`; ~4 % de un núcleo. Prueba: `tests/render_engine_audio.gd`.
- **2026-11-02** — Merge de `origin/main` (garaje de 6 mototaxis, turbo, tierra, motores por vehículo) con
  `main` (juego + sonido). Se conservaron ambos lados en `mototaxi.gd`, `race_hud.gd` y `loading_screen.gd`
  (región y vehículo en el menú). El motor lo pone `VehicleEngineAudio`; `MototaxiAudio` queda con golpes y
  rodadura (`engine_enabled = false`). Con el chasis redondeado la mototaxi se endereza sola: ahora pasar de
  90° y volver también cuesta `flip_damage`. Barra de turbo sobre la de vida.
- **2026-11-02** — Pasajeros con modelo: `Passenger` (6 personajes CC0 de Quaternius en
  `project/assets/characters/`, fuente en `SOURCE.md`). Espera en la vereda derecha del punto de recogida,
  mira y hace señas a la mototaxi a < 45 m, camina hacia ella al subir, baja junto a la mototaxi
  (paga con Interact si llegó a tiempo y ánimo ≥ 0.5; si no, reclama con HitRecieve) y se va caminando.
  La zona de recogida ya no tiene columna de luz. Prueba: `tests/test_passenger.gd` (capturas con ventana).
- **2026-11-02** — Vegetación con modelos reales (`VegetationModels`, fuentes en
  `project/assets/vegetation/SOURCE.md`): árboles comunes y retorcidos, arbustos, helecho y pasto del
  *Stylized Nature MegaKit* de Quaternius (CC0), dos palmeras de Quaternius (CC0) y un cactus órgano
  (Poly by Google, CC-BY 3.0, acreditado en Créditos). Shader `vegetation_textured.gdshader` con la misma
  luz que el terreno; sin desvanecido transparente (las plantas lejanas se veían como fantasmas).
  LOD por planta: modelo completo a < 130 m (`NearVegetation`), versión simplificada más lejos, árboles
  hasta 900 m. Troncos sólidos cerca de la mototaxi (`TreeColliders`, 96 cuerpos reutilizados): chocar un
  árbol a ~43 km/h quita ~11 de vida. Las rutas a campo traviesa esquivan los troncos
  (`TerrainWorld._routing_heights`). Rendimiento (RTX 3050 Laptop, Compatibility): 59–72 FPS (antes 60–109).
  Piloto automático en el terreno del editor: 8/8. En mapas generados (semilla 2026) falla 3/6 por
  pendientes de 0.42; ya fallaba igual sin la vegetación nueva.
- **2026-11-02** — Impostores octaédricos (implementación propia) para los árboles lejanos:
  `tools/bake_impostors.gd` dibuja cada árbol real desde 8×8 direcciones del hemisferio superior
  (proyección hemi-octaédrica) en un SubViewport y guarda dos atlas por especie/variante en
  `project/assets/vegetation/impostors/` (color y normal + hojosidad; 1024², S3TC con mipmaps).
  `shaders/vegetation_impostor.gdshader` dibuja cada árbol lejano con 2 triángulos: elige las 3 vistas más
  cercanas a la dirección de la cámara, proyecta el rayo sobre el plano de cada una y las mezcla con pesos
  baricéntricos (sin saltos al girar); la luz se recalcula con la normal horneada (mismo sol, cielo, niebla y
  sombra del relieve que el terreno). Modelo completo a < 80 m (antes 130), impostores hasta 1.5 km (antes
  900 m). Rendimiento (RTX 3050 Laptop, `benchmark_vegetation.gd -- --editor`): 150–165 FPS, 3–4 M
  triángulos (versión simplificada anterior: 60–69 FPS, 12–14 M). Si se cambian los modelos, volver a
  hornear: `Godot --path project -s res://tools/bake_impostors.gd` (con ventana). Comparar con
  `benchmark_vegetation.gd -- --editor --noimpostor`.
- **2026-11-02** — Menú de pausa (`PauseMenu`): Esc, P o Start del mando abre Continuar / Reiniciar turno /
  Menú principal y un control de volumen general (bus Master). Carrera, sesión y cámara pasan a modo
  pausable (antes heredaban `ALWAYS` de `Main`), así la pausa congela también el reloj del pasajero.
  Prueba: `tests/test_pause_menu.gd`; captura con ventana: `tests/capture_pause_menu.gd -- --editor`.
- **2026-11-02** — Guías estilo GTA: se ocultó la cinta con flechas de la ruta y se quitaron la columna de
  luz, el disco y la luz de las zonas. La recogida no tiene marcador (el pasajero marca el lugar); el destino
  es un anillo plano que sigue el relieve (`GlowZone`). Nuevo `Minimap` (abajo a la izquierda): gira con la
  mototaxi, fondo horneado una vez (región, sombreado del relieve, ríos y lagos; ~0.2–0.8 s al empezar),
  vías y ruta como líneas, objetivo pegado al borde si queda fuera, zoom según la velocidad. Se quitó la
  flecha flotante del HUD. Se anotaron los "Pendientes de jugabilidad" y las opciones para el dinero.
- **2026-11-04** — `juego` avanzada hasta `main` (incluye 036c432: carreteras, iluminación y pasajeros); la
  jugabilidad sigue en `juego`. Dinero con sentido (opciones 1 + 3): pago según el servicio sin propinas
  (`RaceManager.compute_payment`, retraso con margen en vez de fallo inmediato), jornadas con cuota creciente
  (`GameSession`: `day_completed`, "Siguiente día" en `GameOverScreen`), ahorros y compra de mototaxis
  (`CareerSave`, `VehicleGarage`). Mapa completo con M (`FullMap`). HUD: día, reloj, cuota y "TARDE +m:ss".
  Pruebas: `tests/test_jornada.gd` (nueva), `test_race`, `test_s13_juego`, `test_pregame_ui`, `test_passenger`,
  `test_pause_menu`; capturas con `tests/capture_jornada.gd`.
- **2026-11-05** — Guardar partida (pausa) y "Continuar" en el menú principal, con autoguardado al completar
  cada día; antes solo se guardaban los ahorros al terminar un día, así que cerrar el juego a mitad perdía
  todo. Reloj del juego acelerado: la jornada va de 07:00 a 19:00 en 6 min reales. Prueba nueva
  `tests/test_partida.gd`.
- **2026-11-06** — Ahorros por partida: perder borra la partida guardada y sus ahorros; las mototaxis
  compradas se conservan (`CareerSave`: secciones carrera/partida, `get_active`/`set_active`, migración de
  los ahorros antiguos a la partida guardada). Cuota fija por día. Garaje como botón propio del menú
  principal y en el resumen del día (`GameOverScreen.open_garage`); "Nueva partida" sin garaje y con
  confirmación al borrar una guardada; "Reiniciar partida" en la pausa con confirmación. Pruebas actualizadas:
  `test_jornada`, `test_partida`, `test_pregame_ui`, `test_pregame_start`; capturas 8b, 11 y 12 en
  `capture_jornada.gd`.
- **2026-11-06** — Pendiente 7: una sola carrera + Modo libre. Sin "Nueva partida" (con partida guardada el
  menú solo ofrece "Continuar · Día N"); "Cambiar escenario" al terminar el día (el siguiente empieza en el
  mapa nuevo, con los ahorros), al perder (día 1) y en la pausa al reiniciar; Modo libre sin pasajeros,
  reloj ni dinero, con las mototaxis compradas, que reaparece en vez de perder y no toca la carrera.
  Nuevos `ScenarioPicker` (sacado del menú) y `ScenarioPanel`. Prueba nueva `tests/test_escenario.gd`;
  actualizadas `test_partida`, `test_pause_menu`, `test_pregame_ui`; capturas 8c, 9b, 12 y 13.
- **2026-11-06** — Pendiente 8: destinos corto/medio/largo por todo el mapa con recargo por km en los largos
  y sin viajes que no alcancen la jornada (`tests/test_destinos.gd`). Pendiente 10, fase 1: nombres y tipos
  de parada por región (`StopNames`, `tests/test_paradas.gd`); se planteó el resto del plan (fases 2–5) y
  se propuso el pendiente 9 (minimapa para viajes largos).
- **2026-11-06** — Pendiente 10, fase 2: red vial más residencial en C++ (`RoadNetwork::_grow_network`):
  enlaces extra, cuadras en los pueblos, trochas y cruces exactos. `hierarchy_test` actualizado (toda vía
  nueva sale de un punto de otra y el GPS llega a ella); captura nueva `tests/capture_red_vial.gd`.
- **2026-11-06** — Pendiente 10, fase 3: paradas según su lugar en la red (`TerrainWorld._road_sites`,
  `StopNames` con `site`). Anotados los pendientes 11 (vista previa al elegir escenario) y 12 (garaje en
  el Modo libre) y una sección de puntos a mejorar para el equipo de gráficos (nodo `Terrain` rotado que
  hace fallar `textures_test`, vías rústicas, sierra sin vías, pueblos sin casas).
- **2026-11-06** — Pendientes 11 y 12: selector de escenario con tarjetas con foto por región (Mixta,
  Costa, Sierra, Selva) en el menú, el fin del día y la pausa; garaje dentro de la pausa del Modo libre.
  Captura `tests/capture_escenario_ui.gd` (→ `output/ui_review/escenario_*.png`, `libre_*.png`);
  `test_escenario` comprueba el garaje del Modo libre.
- **2026-11-06** — El usuario revisó y aprobó los pendientes 11 y 12. Las fases 4 (casas y ambientación) y
  5 (animales) del pendiente 10 quedan descritas para pedirlas en una sesión nueva ("Fase 4 — cómo
  pedirla", "Fase 5 — cómo pedirla").
- **2026-11-10** — Pendiente 13, fase C: tráfico (`RoadTraffic`): pocos vehículos según tipo de vía y
  dificultad, en tu sentido (más lentos) y de frente (`Difficulty` "oncoming"); otras mototaxis, combi
  hecha por código que para en paraderos, camioneta y camión de Quaternius (CC0, `assets/traffic/`). Frenan,
  esquivan obstáculos fijos, siguen por otras vías; chocarlos = razón `"vehiculo"`. `--trafico=F`. Prueba
  `tests/test_trafico.gd`, capturas `tests/capture_trafico.gd`.
