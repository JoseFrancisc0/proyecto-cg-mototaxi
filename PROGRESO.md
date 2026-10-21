# Progreso del proyecto · Crazy Mototaxi

Seguimiento de lo pedido en `Crazy_Mototaxi_Semana10.pdf` (cronograma S11–S15).
Actualizar este archivo cada vez que se cierre una tarea.

**Ramas**
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
| J-A | Vida: daño por impulso de choque | ⬜ |
| J-A | Detección de vuelco como daño, fin de partida y reinicio | ⬜ (ya existe la detección de vuelco para enderezar) |
| J-B | Ruta A* dibujada en el mundo | ⬜ (`RaceManager.route` ya guarda la ruta) |
| J-B | Flecha de navegación | 🟡 (hay flecha 2D en el HUD hacia el destino en línea recta; falta seguir la ruta) |
| J-B | Tiempo límite según largo **y pendiente** de la ruta | 🟡 (solo largo) |
| — | Fin de partida por tiempo (p. ej. turno total o N fallos) | ⬜ |

### S13 — Integración

| Rol | Tarea | Estado |
|---|---|---|
| J-A | Integrar con la API real; ajustar suspensión y agarre en terreno erosionado | ⬜ |
| J-B | Integrar con la API real | ⬜ |
| J-B | Pasajero que se enoja, propina y puntaje | ⬜ |
| J-B | Pasajeros reales (modelo/personaje) en lugar de zonas brillantes | ⬜ |
| CG-B | Landmarks automáticos por tipo (picos, confluencias, costa) | ⬜ (hoy son los POI de la red de caminos, tipo `"poi"`) |

### S14 — Pulido

| Rol | Tarea | Estado |
|---|---|---|
| J-A | Sonido de motor y choques; balance de vida y daño | ⬜ |
| J-B | Menú con semilla | ⬜ |
| J-B | Minimapa a partir del heightmap | ⬜ |
| J-B | Pantalla final con puntaje | ⬜ |

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

Estado según el PDF de la semana 10; revisar la rama `main` para el detalle actualizado.

| Sem. | Tarea (CG-A / CG-B) | Estado |
|---|---|---|
| S11 | Heightfield C++, flow routing, erosión fluvial y térmica a una resolución | ⬜ |
| S11 | T0 con gradiente costa–sierra–selva; mapas ρ y s₀ por región | ⬜ |
| S12 | Bucle multiescala 256 → 512 → 1024, upsampling bicúbico, deposición | ⬜ |
| S12 | Chunks 128×128, `HeightMapShape3D`, shader de splatting | ⬜ |
| S13 | Retargeting por difusión, pantalla de carga, breaching (opcional) | ⬜ |
| S13 | Ríos desde el drenaje en el shader, landmarks automáticos, caminos sobre terreno erosionado | ⬜ |
| S14 | Figuras del pipeline y tabla de tiempos; niebla, cielo, agua | ⬜ |

---

## Pruebas sin ventana

Desde la raíz del repo (ajustar la ruta del ejecutable de Godot 4.7):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path project -s res://tests/test_terrain_world.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path project -s res://tests/test_mototaxi.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path project -s res://tests/test_race.gd
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

- **2026-10-18** — Ciclo de carrera S11 (J-B) completo: `RaceManager`, `GlowZone`, `RaceHUD` y `tests/test_race.gd`.
  Se devolvió `TerrainWorld` al origen en `main.tscn` (estaba desplazado a y≈96 y rotado, lo que rompía `get_height`).
- **2026-10-19** — Merge de `origin/main` en `juego` y juego sobre el terreno de CG; vías con pendiente
  limitada, transitabilidad, mototaxi con más fuerza en subidas (ver "Integración terreno de CG + juego").
- **2026-10-21** — El juego usa el terreno guardado en `terrain_demo.tscn` (`use_editor_scene`), en vez de
  generar uno con valores por defecto. Nueva prueba `tests/test_editor_scene.gd`.
- **2026-10-21** — `terrain_demo.tscn` guarda solo configuración + suelo (113 MB → 5.6 MB); la malla se
  rehace al abrir. `Terrain` vuelve al origen.
