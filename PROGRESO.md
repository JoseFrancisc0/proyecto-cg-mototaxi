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
3. Aparece la zona **verde** (destino) a 80–260 m; arranca el temporizador.
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
| 5 | Obstáculos en el camino: animales que cruzan o caminan por la vía (estilo Mario Kart), según región: costa perros/gallinas, sierra llamas/alpacas/ovejas, selva chanchos/gallinas; chocar = daño y enojo del pasajero | ⬜ |
| 6 | Otros obstáculos en la vía: piedras de huaico, baches, charcos, otras mototaxis o combis lentas | ⬜ |

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
- **Jornada con cuota.** Cada día dura 6 min (`day_length`); la cuota es S/ 10 el día 1 y sube S/ 4 por día.
  Si el reloj llega a 0 con pasajero a bordo, se termina ese viaje. Con la cuota juntada, lo que sobra va a
  los ahorros y sigue el día siguiente (mototaxi reparada); si no, fin de partida. Ya no se pierde por
  pasajeros perdidos (`max_failures = 0`); siguen el fin por vida, borde y atrapado.
- **Garaje con precios.** `user://carrera.cfg` guarda ahorros, mototaxis compradas y mejor jornada. Se
  empieza con Neon Shadow; las demás cuestan S/ 30–85 (`price` en `VehicleCatalog`) y se compran en el menú.

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
