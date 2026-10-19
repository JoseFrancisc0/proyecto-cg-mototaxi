# (Nombre WIP) Crazy Mototaxi

Trabajo actual: [regiones, drenaje y caminos](docs/s11_cgb.md).

Este nombre no es el final, porque viene con copyright. Mas adelante se le va a poner un mejor nombre.

Integrantes:
- Rodrigo Felix Meza Gavilan
- Josep Ratzinger Castro Ferrer
- Jose Francisco Wong Orrillo
- Jose Joaquin Osnayo Matos

Curso: CS4016 - Computacion Grafica. Ciclo: 2026-2. Universidad: UTEC.

In memoriam Daniel Casquino.

## Escena original y alcance

Se usa `project/terrain_demo.tscn`, su nodo **Terrain** y `project/scripts/chunk_mesh.gd`. Abrir o ejecutar la escena conserva la malla guardada. No se sustituye el generador Perlin/fBm del equipo ni la erosion CG-A de `src/erosion.cpp`.

S11 CG-B distribuye costa, sierra y selva en zonas irregulares, repetibles por semilla, con transiciones suaves. Los mapas regionales de dureza y pendiente critica alimentan CG-A. La distribucion de regiones es una regla del proyecto; no se atribuye al paper.

El flujo autorizado ahora es: relieve regional, CG-A cuando este activo, drenaje, cauces/lagos, red vial y puentes. El mapa configurado mide 1536 por 1536 unidades. La apertura multiescala sigue la composicion de la seccion 5.2 del paper: excavacion distribuida con radios decrecientes y una apertura completa final. El operador completo B usa rutas de salida guiadas por priority-flood; no es una copia literal del algoritmo Barnes citado en el articulo. Las cuadras varian en tamano, orientacion, proporcion e intersecciones. Las carreteras penalizan pendiente y agua; los cruces tienen plataformas elevadas con accesos y no rellenan las zonas protegidas de agua.

## Revisar en Godot

1. Reiniciar Godot despues de compilar para cargar la DLL nueva.
2. Abrir `project/project.godot`, la escena **terrain_demo.tscn** y seleccionar **Terrain**.
3. **1. Generar terreno nuevo (T0)** crea el terreno desde el ruido con la configuracion del Inspector (regiones, rios con **Hydrology Enabled**, caminos con **Preview Roads**). No aplica erosion.
4. **2. Aplicar erosion al terreno actual** erosiona el terreno visible con los pasos del grupo *Erosion (paper)*. No genera uno nuevo: cada clic se acumula y los rios y caminos se recalculan encima del suelo erosionado. Si se cambiaron parametros del terreno en el Inspector, se ignoran (aviso en Salida) hasta generar un T0 nuevo.
5. **Volver a la version guardada** restaura la malla guardada en la escena junto con su configuracion.

Al guardar la escena (Ctrl+S) se guardan juntos la malla, la configuracion con que se genero (`terrain_snapshot`, incluido el historial de erosiones) y el suelo (`ground_bytes`: T0 + erosiones, sin rios ni caminos). Al abrir la escena, el Inspector muestra esa configuracion. Prueba: `tests/workflow_test.gd`.

### Texturas (S10)

El terreno se pinta con 7 texturas de ambientCG segun region, pendiente y altura (`shaders/terrain_splat.gdshader`):

| Capa | ID ambientCG | Uso |
|---|---|---|
| 0 | Ground054 | Costa, plano (arena) |
| 1 | Rocks021 | Costa, ladera (piedras sobre arena) |
| 2 | Rocks007 | Sierra, plano (roca con pasto) |
| 3 | Rocks011 | Sierra, ladera (lajas, triplanar) |
| 4 | Snow015 | Sierra, cumbre (20% mas alto del mapa) |
| 5 | Ground037 | Selva, plano (musgo) |
| 6 | Rock059 | Selva, ladera (roca verde, triplanar) |

- Descomprimir cada `.zip` 2K-JPG dentro de `project/textures/` (queda `textures/Ground054_2K-JPG/Ground054_2K-JPG_Color.jpg`, etc.). Se usan `_Color`, `_NormalGL` y `_Roughness`. Si falta un archivo se usa un color plano y se avisa en Salida.
- Son texturas CC0 de ambientCG. Si no se suben a git por su peso, cada integrante las descarga con los mismos IDs. El cache `textures/_cache/` se genera solo y no se sube.
- C++ agrega a cada vertice la UV `(x, z)` en metros (parametrizacion planar) y `CUSTOM0 = (peso costa, peso sierra, peso selva, humedad)`. El alfa del color de vertice es la mascara de caminos.
- Una malla guardada antes de S10 no trae esos datos: se ve con colores por vertice hasta generar un T0 nuevo.
- Ajustes finos en **Terrain > Material Override**: `tile_size`, pendientes, `normal_strength`, `debug_view` (1 = color por material, 2 = regiones, 3 = ajedrez de UV). **Use Textures** apaga las texturas; **Recargar texturas** relee la carpeta e imprime que archivo usa cada capa.
- El material con texturas no se guarda dentro del `.tscn`: se arma al abrir la escena.
- Prueba: `tests/textures_test.gd`.

### Iluminacion (S12)

El shader calcula su propia luz (`render_mode unshaded`), con tecnicas del silabo 6.3.3:

1. **Blinn-Phong**: difusa `N.L`, especular `(N.H)^s` y ambiente hemisferico (cielo arriba, suelo abajo).
2. **Sombras por ray tracing en GPU**: desde cada pixel se lanza un rayo hacia el sol sobre el mapa de alturas de la malla (`height_map`). Si pasa por debajo del terreno, hay sombra; la distancia minima al terreno da la penumbra.
3. **Iluminacion global (AO)**: en C++ (`sky_visibility` en `terrain_mesh.cpp`) cada vertice lanza 16 rayos sobre el heightfield y guarda que fraccion del cielo ve (`CUSTOM1`). Oscurece quebradas y valles.
4. **POM**: ray marching dentro del mapa `_Displacement` de cada textura, solo cerca de la camara.
5. **Niebla por distancia** y **tone mapping ACES**.

- El sol se mueve con **Sun Azimuth** y **Sun Elevation** (grupo *Iluminacion (S12)* del Inspector). Tambien orienta el nodo `Lighting`, que ilumina agua y puentes.
- Ajustes en Material Override: grupos *Iluminacion*, *Sombras*, *Relieve_POM* y *Atmosfera*. `debug_view`: 4 = solo sombras, 5 = solo AO, 6 = texturas sin luz.
- Una malla generada antes de S12 no trae `CUSTOM1`: generar un T0 nuevo.

Guardar despues de generar conserva la nueva vista, incluyendo agua y puentes. La copia mas reciente de la escena del usuario, semilla 123, esta en `output/backups/terrain_before_hydrology_seed123.tscn`. No restaurar copias antiguas sobre cambios recientes del usuario.

El agua es estatica. Los puentes son superficies visuales: faltan colisiones de vehiculo, barandas y validacion de pendientes de conduccion. No se da por completado S12/S13. La API de TerrainWorld consulta alturas y drenaje finales despues de generar; landmarks permanece pendiente y su ruta sugerida no es navegacion de trafico por calles.

## Compilar y probar

En PowerShell, desde la raiz:

```powershell
.\tools\build.ps1
.\tools\run.ps1 -Tests
```

En este equipo SCons y LLVM-MinGW estan dentro de `.tools/`, excluido de Git. En otra maquina se requiere Godot 4.7, Python, SCons, godot-cpp y compilador C++ de 64 bits. Con Visual Studio Build Tools, usar x64 Native Tools Command Prompt:

```text
python -m pip install scons
git submodule update --init --recursive
python -m SCons platform=windows target=template_debug arch=x86_64 api_version=4.7 build_profile=build_profile.json -j8
```

## Codigo

| Archivo | Funcion |
| --- | --- |
| `src/terrain_noise.*` | Perlin/fBm original, regiones, pesos y mapas rho/s0. |
| `src/erosion.*` | Erosion CG-A multiescala existente. |
| `src/drainage.*` | Receptores, acumulacion en m2, cauces y lagos despues de CG-A. |
| `src/road_network.*` | Poblados variables y carreteras sobre la superficie generada. |
| `src/terrain_mesh.*` | Orden del proceso, proteccion de cauces y geometria de terreno/agua/puentes. |
| `project/scripts/chunk_mesh.gd` | Controles de la escena original y restauracion. |
| `project/scripts/terrain_world_stub.gd` | Consultas de superficie y drenaje; landmarks pendiente. |

Las siete pruebas incluyen continuidad descendente hasta salidas, conservacion del area aportante, proteccion de agua frente a relleno vial, reproducibilidad, conectividad de calles y restauracion. Las pruebas de integracion de CG-A usan pocas iteraciones; no sustituyen la revision del preset completo.



## Rios: estado actual despues de revisar el paper

Ya no se llenan depresiones para crear lagunas automaticas ni se limita su cantidad con cuotas. **Max Lakes** y **Max Lake Area** se retiraron del Inspector. Con hidrologia activa, el flujo es: regiones, CG-A opcional, apertura multiescala del terreno real, recalculo del drenaje, agua y caminos/puentes.

La apertura sigue la estructura de la seccion 5.2 (paginas 7-8): T_siguiente = T - suavizado(T - B(T)), reduciendo el radio a la mitad; termina con B completo para garantizar salida. Esta implementacion CPU usa un B propio guiado por priority-flood y un kernel compacto de caja separable; no es una reproduccion exacta de Barnes ni de todos los detalles del codigo de los autores. El drenaje posterior usa los ocho vecinos inferiores y pesos de pendiente elevados a 1.3, como la seccion 4.1 y CG-A. Los receptores y cotas publicados corresponden al terreno abierto, no a un nivel virtual de inundacion.

**Breach Radius** (24 m) ajusta el radio inicial de distribucion de la excavacion; no es un limite de profundidad. **River Catchment** (60000 m2) selecciona los cauces visibles: subirlo muestra menos ramificaciones. Cambiar ese umbral no vuelve a excavar el terreno: el agua es una representacion del drenaje ya calculado. No hay simulacion temporal de agua. Las depresiones encerradas pueden requerir cortes profundos; no se garantiza conservar cada cumbre, ya que el retargeting del paper sigue pendiente en esta escena. La malla guardada se conserva para comparar.

La prueba nativa usa una depresion rodeada de una barrera: comprueba que solo se retira material, que no quedan sumideros interiores, que todo el aporte alcanza el borde, y que la misma entrada produce el mismo resultado. Las pruebas Godot comprueban continuidad, proteccion de los cauces, geometria orientada hacia arriba y restauracion de los detalles guardados. CG-A completo aun requiere revision visual con el preset de produccion.


Correccion visual: la escena con semilla 96 tenia River Catchment=100, lo que convertia tributarios pequenos en una capa extensa. Se ajusto solo ese parametro a 60000 preservando cada byte de las mallas guardadas; copia en output/backups/terrain_before_water_fix_seed96.tscn. El umbral efectivo minimo es el 1% del area del mapa. El agua visible ahora es mas estrecha y omite tramos de pendiente superior al 20%; esos tramos conservan el drenaje, pero no se representan como cascadas. Las secciones transversales de agua se mantienen horizontales, sin proyectarlas sobre paredes de barrancos. Se reviso una captura real de Godot: output/s11_cgb/water_fix_godot.png. Persisten incisiones estrechas del operador B propio; esta vista es experimental y no equivale a reproducir exactamente la calidad visual del paper.
