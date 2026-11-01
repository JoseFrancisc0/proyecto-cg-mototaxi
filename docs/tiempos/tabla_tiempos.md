# Tabla de tiempos por resolucion

Medido con `tests/benchmark_resoluciones.gd` el 2026-10-25 20:39:51. CPU: Intel(R) Xeon(R) Processor @ 2.10GHz, 2 hilos (la erosion reparte las filas en hasta 8 hilos). Mapa de 1536 m, semilla 2, 30 iteraciones por medicion.

## Milisegundos por iteracion (comparar con la Tabla 2 del paper)

| Resolucion | Fluvial | Termica (mapa s0) | Termica (ruido, como el repo) | Deposicion | Paper GPU: fluvial / termica / deposicion |
|---|---|---|---|---|---|
| 129 x 129 | 1.443 | 0.766 | 3.682 | 2.747 | 0.025 / 0.006 / 0.030 |
| 257 x 257 | 5.101 | 2.378 | 9.458 | 6.534 | 0.027 / 0.007 / 0.055 |
| 513 x 513 | 17.738 | 5.084 | 33.011 | 19.030 | 0.093 / 0.018 / 0.188 |
| 1025 x 1025 | 62.471 | 18.531 | 109.561 | 69.572 | 0.330 / 0.060 / 0.690 |

La termica del juego usa el mapa regional s0(p) (paper 4.3); sin el, el repo oficial evalua ruido simplex 3D en cada celda y cada iteracion, que cuesta mas.

El paper corre en una GPU (GTX 3080) con compute shaders; aqui es el port en CPU con hilos. El costo por iteracion crece con el numero de celdas (x4 al duplicar la resolucion), igual que en el paper.

## Otras etapas (segundos)

| Resolucion | T0 | Retargeting | Breaching | Drenaje | Rios (SDF) | Red vial | Caminos en malla | AO (ray tracing) | Malla | Vegetacion | Chunks |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 129 | 0.01 | 0.05 | 0.01 | 0.01 | 0.00 | 0.11 | 0.01 | 0.01 | 0.00 | 0.06 (63653 plantas) | 0.00 (1) |
| 257 | 0.02 | 0.16 | 0.04 | 0.02 | 0.01 | 0.09 | 0.04 | 0.09 | 0.02 | 0.08 (61665 plantas) | 0.02 (4) |
| 513 | 0.09 | 0.29 | 0.15 | 0.07 | 0.03 | 0.08 | 0.12 | 0.34 | 0.08 | 0.11 (60913 plantas) | 0.08 (16) |
| 1025 | 0.34 | 1.01 | 0.97 | 0.29 | 0.13 | 0.09 | 0.54 | 1.49 | 0.32 | 0.16 (60705 plantas) | 0.28 (64) |

## Receta completa del paper (estimada)

Base 129 y la receta de `PredefinedErosion()` por nivel: 3000/600/2000, 1500/1000/700, 700/2000/200, 400/6000/150.

| Mapa final | Niveles | Tiempo estimado | Detalle por nivel |
|---|---|---|---|
| 129 x 129 | 0 | 10 s (0.2 min) | 129: 10.3 s |
| 257 x 257 | 1 | 25 s (0.4 min) | 129: 10.3 s, 257: 14.6 s |
| 513 x 513 | 2 | 51 s (0.9 min) | 129: 10.3 s, 257: 14.6 s, 513: 26.4 s |
| 1025 x 1025 | 3 | 198 s (3.3 min) | 129: 10.3 s, 257: 14.6 s, 513: 26.4 s, 1025: 146.6 s |

Comprobacion: la receta completa real a 513 tardo 43.5 s.
