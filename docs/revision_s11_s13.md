> Documento historico de la integracion anterior, ahora desconectada. El alcance y estado actual estan en [S11 CG-B](s11_cgb.md). Las afirmaciones de integracion S12/S13 de este documento NO describen el proyecto activo.

# S11, S12 y S13: integración en la escena original

Fecha: 16 de octubre de 2026. Alcance: CG-A y CG-B.

## Escena de trabajo

**`project/terrain_demo.tscn` sigue siendo la escena inicial.** El nodo `Terrain`, su transformación, la malla guardada, la luz y la cámara se conservan. El controlador sigue en `project/scripts/chunk_mesh.gd`.

Al generar, ese controlador crea `Terrain/TerrainWorld/Chunks` y `Terrain/Landmarks`. Se oculta únicamente la instancia de render de la malla antigua para evitar superposición; no se borra su recurso guardado. En el editor, el botón **Regenerar terreno** permite comprobar la integración. Los nodos generados son temporales; en ejecución se reconstruyen automáticamente.

`world_demo.tscn` fue una escena auxiliar creada durante la asistencia. No forma parte del flujo de trabajo principal y no se usa para justificar la integración en la escena original.

## Trabajo previo reconocido

El equipo ya había implementado en `src/erosion.cpp` y `src/erosion.h` el núcleo de CG-A para **S11 y S12**: heightfield, flow routing, erosión fluvial y térmica, deposición, interpolación bicúbica y bucle multiescala. Ya estaba llamado desde `TerrainMesh` y el script de la escena original.

La asistencia no debe atribuirse esos algoritmos. Aportó pruebas, correcciones y optimizaciones, y añadió el almacenamiento compartido necesario para integrar CG-B y S13. El ruido del equipo sigue siendo T0 en la escena original; se mezcla hacia una llanura en la costa, sin sustituir el relieve interior por el relieve del visor auxiliar.

## Estado por entrega

| Semana | CG-A | CG-B |
| --- | --- | --- |
| S11 | Núcleo existente conservado. Comparación independiente CPU/GPU de las tres etapas, con el mismo input, aprobada en una prueba acotada. | Pesos costa/sierra/selva con fronteras deformadas; mapas regionales de dureza y pendiente crítica; API TerrainWorld y modo stub conectables al juego. |
| S12 | Erosión multiescala existente reutilizada. Escena ajustada a 256→512→1024 celdas, con dos ampliaciones. Tiempos por etapa y resolución. | 64 chunks de 128×128 celdas, colisiones HeightMapShape3D y shader con texturas originales CC0. |
| S13 | Retargeting por difusión y generación desde semilla con carga sin bloquear la interfaz. | Ríos pintados desde drenaje, landmarks automáticos y rutas A* sobre alturas posteriores a erosión/retargeting; integración en Terrain. |

**Breaching sigue sin implementarse:** es opcional en el cronograma. El estado anterior describe funciones implementadas; no es una certificación académica ni implica haber reproducido todas las figuras del artículo.

## Parámetros de la escena

- Se conserva la semilla 68, el tamaño de celda 0.75 y el mapa de 1024 celdas.
- Se ajusta `erosion_levels` de 3 a 2: antes partía de 128 celdas, ahora parte de 256 como pide el cronograma.
- Las iteraciones originales del inspector siguen siendo 3000 fluviales, 600 térmicas y 2000 de deposición en el primer nivel. Los siguientes niveles usan la receta existente.
- Por defecto se conserva el 100% de iteraciones. El modo rápido usa 3% y se identifica en pantalla.
- Se habilitan seis puntos y dos vecinos para mostrar los caminos, que estaban desactivados. Separación, anchura, transición y suavizado se envían desde el inspector al módulo compartido.
- El mapa cuenta celdas: 1024 celdas son 1025 muestras por lado. Cada chunk tiene 129×129 muestras, compartiendo bordes.

## Validación realizada

1. Compilación real de la DLL Windows x64 con SCons y LLVM-MinGW portable, instalada dentro de `project/bin/windows`.
2. Pruebas básicas: semilla reproducible, malla, erosión pequeña y alturas finitas.
3. Pruebas TerrainWorld: pesos normalizados, mapas regionales, bordes compartidos, rutas sobre alturas finales, retargeting con restricciones y colisiones a tamaño de celda 0.75.
4. Prueba específica de **terrain_demo.tscn**: conserva el recurso de malla original, genera chunks bajo Terrain, utiliza la cámara existente y alinea la colisión con la transformación original. También comprueba que T0 conserva el ruido del equipo fuera de la costa.
5. Captura real de la escena original a 1024 celdas y 64 chunks: aproximadamente **3.03 s de cálculo C++** con el 3% de iteraciones en este equipo.
6. Comparación con los shaders oficiales de H-Schott/MultiScaleErosion: error máximo aproximado de **0.0000093** en fluvial y **0.0000032** en térmica/deposición. Se probaron 12, 4 y 4 iteraciones, respectivamente, con 257 muestras por lado y sin mapas regionales propios. No equivale a comparar toda la receta completa.

Las mediciones previas de 160 s y 258 s correspondían al generador auxiliar y a versiones anteriores. No deben presentarse como el tiempo medido de la escena original integrada. Sus datos se conservan únicamente como referencia histórica.

## Límites y comprobaciones finales

- Los ríos son representación del drenaje en el shader, no una simulación dinámica de agua.
- Sin breaching pueden quedar pozos y discontinuidades hidrológicas.
- Los valores regionales y el aspecto visual necesitan revisión del equipo; las pruebas no sustituyen esa decisión artística.
- La altura consultada usa interpolación bilineal; la colisión usa triángulos. Puede haber pequeñas diferencias dentro de una celda.
- La cámara añadida solo cambia su encuadre durante ejecución; el nodo Camera de la escena se conserva.
- La implementación de vehículo y carreras sigue fuera de esta revisión (J-A y J-B).

## Ejecutar

```powershell
.\tools\build.ps1
.\tools\run.ps1 -Tests
.\tools\run.ps1 -Quick
```

En Godot: importar `project/project.godot`, abrir `terrain_demo.tscn` y pulsar F5/F6. Para recompilar, cerrar antes las instancias de Godot que tengan cargada la DLL.
