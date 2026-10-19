# Progreso del proyecto · Crazy Mototaxi

Seguimiento de lo pedido en `Crazy_Mototaxi_Semana10.pdf` (cronograma S11–S15).
Actualizar este archivo cada vez que se cierre una tarea.

**Ramas**
- `main`: terreno y realismo (erosión multiescala del paper *Terrain Amplification using Multi-scale Erosion*).
- `juego`: jugabilidad (vehículo, carreras, HUD) sobre el terreno provisional (stub de `TerrainWorld`).

Leyenda: ✅ hecho · 🟡 en curso / parcial · ⬜ pendiente

---

## Jugabilidad (rama `juego`)

### S11 — Hito: "Mototaxi manejable que recoge a un pasajero"

| Rol | Tarea | Estado | Dónde |
|---|---|---|---|
| CG-B | API `TerrainWorld` publicada con stub (`generate`, `get_height`, `get_normal`, `get_biome`, `get_drainage`, `get_landmarks`, `find_route`) | ✅ (stub: sin costa, `get_drainage` = 0) | `project/scripts/terrain_world.gd` |
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

Si se agregó un script con `class_name` nuevo, correr antes una vez `--headless --path project --import`
para que Godot registre la clase.

## Registro

- **2026-10-18** — Ciclo de carrera S11 (J-B) completo: `RaceManager`, `GlowZone`, `RaceHUD` y `tests/test_race.gd`.
  Se devolvió `TerrainWorld` al origen en `main.tscn` (estaba desplazado a y≈96 y rotado, lo que rompía `get_height`).
