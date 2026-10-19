> Estado actual: la integracion vigente de rios se documenta en README.md, apartado "Rios: estado actual despues de revisar el paper". Las notas previas de priority-flood con llenado, lagunas por cuota y posterior filtrado quedan como historial y ya no describen el comportamiento actual. Se aplica breaching multiescala y drenaje sobre alturas reales; los controles Max Lakes y Max Lake Area fueron retirados.

# S11 CG-B: regiones sobre el generador existente

## Objetivo y alcance

Mantener el estilo del terreno del equipo y generar costa, sierra y selva variando parametros del mismo Perlin/fBm. La misma semilla reproduce alturas y regiones; otra semilla cambia el ruido y la distribucion. Se trabaja en `project/terrain_demo.tscn`, no en otra escena.

Abrir la escena no cambia la malla guardada. El boton T0 genera ruido, regiones y, si `preview_roads` esta activo, los caminos A* del generador existente. No ejecuta erosion, retargeting ni el generador auxiliar. El boton de restauracion vuelve al recurso que estaba cargado al abrir la escena. Se conserva una copia completa en `output/backups/terrain_demo_before_s11_cgb.tscn`.

## Relacion correcta con el paper

- **Figura 3 y seccion 3:** T0 es el terreno de entrada del sistema de amplificacion. El articulo acepta entradas creadas mediante ruido procedural; no prescribe un generador de regiones peruanas.
- **Distribucion regional, propia del proyecto:** zonas Voronoi ponderadas, con centros desplazados por la semilla, tamanos variables y fronteras deformadas por Perlin. Las zonas reciben biomas repetibles; se garantiza presencia de las tres regiones, sin orden ni cuotas de area iguales. Cada bioma puede ocupar varias zonas separadas y costa puede tocar selva sin sierra intermedia. Los pesos continuos suman uno y mezclan los parametros del fBm existente.
- **Seccion 4.2:** el mapa de dureza rho(p) controla `k(p) = k * (1-rho(p))`. Una dureza cercana a uno protege el terreno. Se mezcla la dureza por region y se introduce una variacion fractal suave en sierra.
- **Seccion 4.3:** el mapa de pendiente critica s0(p) representa `tan(gamma0(p))`, no grados. Se mezcla por region y se varia suavemente en sierra.

Los coeficientes regionales son valores iniciales del proyecto, **no valores prescritos por el paper**. El codigo indica que parte procede del articulo y que parte es una decision de diseno.

## Parametros iniciales

| Parametro | Costa | Sierra | Selva |
| --- | ---: | ---: | ---: |
| Altura base | -8 | 35 | -10 |
| Amplitud | 8 | 55 | 15 |
| Frecuencia | 0.005 | 0.006 | 0.005 |
| Dureza rho | 0.10 | 0.65 | 0.35 |
| Pendiente critica s0 | 0.25 | 1.15 | 0.60 |

Los valores sierra/selva de altura y ruido conservan los parametros del generador anterior. Se mantienen sus tres octavas, lacunaridad y persistencia. No se impone una envolvente senoidal que reemplace todas las montanas por un pico.

`transition_width` controla el ancho relativo de mezcla (por defecto 0.16 del dominio proyectado). `border_warp` controla cuanto deforma el ruido las fronteras (0.16 inicialmente). `three_regions = false` permite recuperar la funcion de alturas anterior. `region_patches` controla cuantas zonas regionales se distribuyen (16 inicialmente, entre 6 y 32). Zonas vecinas del mismo bioma pueden unirse; otras quedan separadas. El numero de zonas no equivale al numero final de componentes de cada bioma.

## Conexion con CG-A

`TerrainMesh` sigue llamando a `erode_terrain`, implementado por el equipo para S11 y S12 CG-A. Cuando se elige explicitamente regenerar con erosion y se habilita `use_regional_erosion_maps`, se muestrean rho y s0 y se suministran al codigo existente. Se conservan semilla 68, 1024 celdas, celda 0.75 y tres ampliaciones. Se habilitan ocho destinos y dos vecinos para los caminos; la malla guardada no se sustituye al abrir.

La vista T0 se calcula desde cero con el ruido original; no toma la malla ya erosionada para erosionarla una segunda vez. La malla guardada sigue siendo una referencia distinta del T0 generado.

## API provisional para el juego

El nodo `Terrain/TerrainWorld` es `TerrainWorldStub`, con `is_stub = true`.

| Metodo | Resultado en S11 |
| --- | --- |
| `generate(seed)` | Actualiza el generador provisional de T0. No promete construir el mundo final. |
| `get_height(x,z)` y `get_normal(x,z)` | Consultas sobre T0, en coordenadas locales de Terrain. |
| `get_biome(x,z)` | Vector3 de pesos costa/sierra/selva. |
| `get_hardness(x,z)` | Dureza rho. |
| `get_critical_slope(x,z)` | Pendiente s0. |
| `get_drainage(x,z)` | Cero, placeholder explicito. |
| `get_landmarks()` | Lista vacia, placeholder explicito. |
| `find_route(a,b)` | A* existente sobre T0. |

Las consultas de este stub no deben usarse como alturas exactas de la malla erosionada guardada. La API real sobre terreno final pertenece a una integracion posterior.

## Verificacion

- Compilacion real Windows x64, DLL copiada a `project/bin/windows`.
- Pruebas de ocho semillas, incluidas negativas y extremos de int32: tres regiones presentes.
- Pesos normalizados, alturas finitas, continuidad muestreada, dureza en [0,1] y pendiente positiva.
- Reproducibilidad y recuperacion del comportamiento anterior al desactivar regiones.
- Con los parametros predeterminados y semilla 68 se detectaron 26 maximos locales en la zona de sierra en una grilla de muestreo 97x97 con la distribucion anterior por franjas. Con las nuevas zonas irregulares se detectaron 11 maximos locales para esa misma semilla. Es una comprobacion del relieve de esa configuracion, no una garantia para cualquier parametro.
- Prueba de escena: abrir conserva el mismo recurso de malla/material; generar T0 coincide con el stub y restaurar recupera los recursos originales.
- Se modificaron solo los valores de destinos/vecinos en la escena para habilitar caminos. El bloque serializado ArrayMesh se comparo con la copia previa y sigue identico; su SHA256 normalizado es `d201f75bba387bcefec7c30a0eb05e56769b2245b49d05e7e65d3d503285a048`.

Vista numerica actual: `output/s11_cgb/regiones_irregulares_caminos.png`. Compara regiones y caminos de cuatro semillas; no representa el resultado erosionado. La altura esta exagerada x3 solo para facilitar la inspeccion visual.

No se certifican S12 CG-B ni S13 en esta entrega. No se ejecuta ninguna de esas integraciones al abrir la escena original.


## Caminos y verificacion del 18 de octubre

Se reutiliza el A* y el aplanado original de `RoadNetwork`/`TerrainMesh`. Se permite ubicar destinos en las tres regiones; el costo de A* penaliza los desniveles. Se conecta cualquier grupo aislado de la red de vecinos con el grupo mas cercano. Esto no sustituye las pruebas de conduccion/suspension posteriores.

El aplanado se rasteriza alrededor de cada segmento, en lugar de comparar todos los vertices con todos los segmentos. Se verifico numericamente que conserva el mismo perfil del segmento mas cercano. Los parametros `num_points`, `k_neighbors`, `min_point_dist`, `road_width`, `road_fade` y `road_smooth` siguen disponibles en el inspector.

`preview_roads` permite incluir o quitar caminos de la vista T0 sin ejecutar erosion. Al desactivarlo se puede comparar el ruido con la API stub; con caminos, las alturas aplanadas pueden diferir del T0 que consulta ese stub. La integracion de rutas y consultas sobre el terreno final erosionado sigue siendo una tarea posterior.

Pruebas actuales: regiones en ocho semillas; continuidad y reproducibilidad; multiples picos; caminos reproducibles y conectados; aplanado consistente; apertura/restauracion de la escena sin perder la malla. En las semillas 68, 2026, 1337 y 42 se midieron dos componentes de costa significativos y contactos costa-selva. Las proporciones respectivas son aproximadamente 26/12/62, 30/45/25, 37/43/20 y 28/48/24 por ciento (costa/sierra/selva). Estos son resultados de esas semillas, no cuotas impuestas.


## Ampliacion y red vial (18 de octubre)

La escena original conserva su ArrayMesh guardado y la semilla 147. Para la siguiente generacion se amplia el lado de 768 a 1536 unidades (cell_size 1.5, grid_size 1024): cuatro veces el area, con menor densidad de muestras por metro. La copia anterior esta en output/backups/terrain_before_streets_20261018.tscn. Abrir la escena no regenera ni aplica erosion.

El Inspector permite activar hierarchical_roads y ajustar town_count, block_size y los anchos completos highway_width (14), avenue_width (10), street_width (6). Se buscan emplazamientos con menor pendiente en su entorno, separados entre si. Cada poblado tiene cuatro cuadras, avenidas centrales y calles perimetrales; las carreteras unen los centros mediante un arbol conectado mas una ruta alternativa. A* considera distancia y desnivel; su rejilla se limita a 513 muestras por lado. Los trazados son reproducibles con la semilla. El asfalto se representa mediante color de vertices y el terreno adopta el perfil de cada via.

Esta red es una regla de diseno para el videojuego sobre T0; no se atribuye al paper. No incorpora edificios, aceras, intersecciones con prioridad de trafico ni garantiza una pendiente maxima de conduccion. Los controles regionales del paper y la erosion CG-A mantienen su funcion anterior.

Verificacion: compilacion C++ y seis pruebas sin errores, incluida conectividad por extremos compartidos, limites del mapa, anchos y reproducibilidad de 4 carreteras, 16 tramos de avenida y 32 tramos de calle para la semilla 147. Se verifico por comparacion binaria que el unico cambio de la escena guardada es cell_size. El diagrama output/s11_cgb/red_vial_ampliada.png procede de los trazados reales exportados por la prueba; no es una captura del terreno en Godot.

Para verlo: reiniciar Godot para cargar la extension compilada, abrir project/terrain_demo.tscn, seleccionar Terrain y pulsar Generar T0. Volver a la malla guardada restaura la vista anterior durante la sesion.


## Drenaje y vias: integracion posterior

Se mantiene CG-A. Se anade priority-flood (`drainage.cpp`) despues de erosion: salidas en bordes, receptores sin ciclos, area aportante en m2 y lagos en depresiones cerradas. Es una integracion del juego adicional al paper, no un reemplazo ni una tecnica atribuida al articulo. No se excavan montanas completas para vaciar lagos. Los cauces superan river_catchment (12000 m2) y reciben incision localizada y agua estatica. La vista previa omite CG-A pero puede mostrar esta hidrologia; para T0 puro desactivar hidrologia y caminos.

La red jerarquica se reconstruye sobre las alturas finales despues de erosion y drenaje. A* penaliza pendiente y agua. Las celdas de cauces y lagos protegidas no se modifican por caminos; los cruces reciben plataformas elevadas con accesos. Las cuadras alternan 2 o 4 por lado, con proporcion, orientacion y nodos compartidos variables.

La API de TerrainWorld mantiene landmarks pendiente, pero alturas y drenaje ya usan datos generados. La ruta sugerida es sobre suelo, no un navegador de calles/puentes. Agua y puentes se pueden guardar con la escena y restaurar junto con la malla. Son superficies visuales sin colisiones de vehiculos ni validacion de pendiente maxima.

Validacion: siete pruebas Godot sin errores; CG-A se prueba con pocas iteraciones en una malla reducida, no con el preset completo. La vista completa T0 de 1024 celdas, 1536 m y semilla diagnostica 147 tardo 1.85 s en este equipo. `rios_y_calles.png` es un plano muestreado, no una captura de Godot; el azul incluye margenes protegidos de orilla. La escena del usuario ahora tiene semilla 123 y se conserva. Copia adicional: `output/backups/terrain_before_hydrology_seed123.tscn`.


### Menor densidad de agua

El umbral inicial river_catchment sube de 12000 a 60000 m2. El calculo conserva todos los receptores y la acumulacion, pero no representa cada depresion potencial como agua visible: selecciona hasta max_lakes=2 depresiones compactas, de hasta max_lake_area=5000 m2 cada una. Las depresiones descartadas quedan secas en la vista. Se muestran solo tramos de rio conectados aguas abajo a una salida sin atravesar depresiones descartadas; no se dibuja agua flotando sobre ellas. Es un control visual del paisaje del juego, no una simulacion fisica del balance de agua. Los caminos protegen las aguas visibles. Max Lakes=0 permite desactivar las lagunas manteniendo los cauces. La escena guardada no se modifica: regenerar para aplicar los nuevos controles.


### Controles de agua y jerarquia del relieve

En Terrain > Rios y drenaje, Max Lakes limita la cantidad, Max Lake Area la superficie maxima por laguna en m2 (no radio ni profundidad), y River Catchment el area aportante necesaria para representar un cauce: subirlo reduce rios; bajarlo los aumenta. Max Lake Area descarta depresiones demasiado extensas; no garantiza ni recorta un tamano exacto. Los rios siguen las pendientes y la semilla, no ubicaciones fijas. AguaGenerada contiene las superficies azules de rios y lagunas. No hay un control expuesto de ancho del rio: el C++ lo deriva de acumulacion, entre 4 y 8 unidades de ancho completo.

Nuevos valores de base/amplitud/frecuencia: costa 4/4/0.003, selva 28/14/0.004, sierra 130/85/0.008. Son decisiones del mapa del juego, no altitudes geograficas de Peru ni parametros prescritos por el paper. El rango teorico en interiores puros queda separado: costa [0,8], selva [14,42], sierra [45,215]; los valores observados son mas estrechos. Las transiciones siguen siendo continuas y pueden tener altitudes intermedias.

Cada region evalua el mismo Perlin/fBm original con sus parametros y despues se mezclan las alturas. Ya no se interpola la frecuencia espacial antes de evaluar el ruido, porque ese cambio de fase generaba crestas ajenas al relieve de cada region. El generador sin regiones permanece igual. La prueba regional_relief_test verifica alturas y pendientes interiores en tres semillas. La escena guardada se conserva; regenerar para ver el relieve nuevo.
