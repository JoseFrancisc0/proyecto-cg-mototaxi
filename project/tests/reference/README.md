# Referencia independiente

Los tres archivos `.glsl.txt` provienen de:
https://github.com/H-Schott/MultiScaleErosion/tree/main/data/shaders

Descargados el 16 de octubre de 2026. Su licencia original se conserva en `LICENSE.txt`.

La prueba `reference_compare.gd` ejecuta esos shaders en Vulkan y compara sus alturas con el port CPU usando el mismo T0, escala de 20 km, semilla 68 y 257 muestras por lado. No habilita mapas regionales en esta comparación, porque el shader fluvial oficial declara la dureza pero no la aplica. El shader se adapta en memoria: uniforms OpenGL pasan a constantes y se define COMPUTE_SHADER. Los archivos originales permanecen intactos.

Se comparan por separado 12 iteraciones fluviales, 4 térmicas y 4 de deposición. Tolerancia absoluta: 0.02 unidades de mundo. Esta prueba no demuestra equivalencia de toda la receta de miles de iteraciones ni valida las modificaciones regionales propias.
