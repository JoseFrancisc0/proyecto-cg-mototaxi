# Recuperación de la base vial original

Se consultó `origin/juego` hasta `324bc3f`. Su trazador `src/road_network.cpp` coincide con el que ya estaba en `main`: el problema principal estaba en la integración posterior del mundo. No se hizo un merge completo ni se creó otra rama.

## Correcciones

- `TerrainWorld` vuelve a usar la superficie final de CG (`get_surface_heights`), con sus carreteras, en lugar del terreno anterior al rasterizado de vías. Se retiran las sustituciones de parámetros de relieve y distribución regional añadidas en la integración peruana.
- La capa peruana conserva los puntos, las alturas y los anchos nativos. La nivelación de poblados y los ríos no vuelven a modelar sus calzadas. Los lechos bajo tableros pueden ajustarse al agua; quedan protegidos de la nivelación posterior de poblados.
- El rasterizador original recibe una corrección localizada: el suelo alcanza el perfil limitado en pendiente, sin truncar el movimiento de tierra a cinco metros. Las banquinas mezclan ese ajuste con el terreno según la magnitud de corte o relleno. No se cambia la búsqueda de rutas ni su redondeo.
- Se conservan los tableros nativos y su colisión. El mismo generador completa los tramos secos expuestos donde los triángulos del terreno no alcanzan el perfil. No se crean tableros adicionales por confundir un cruce con la huella de otra rampa.
- Los caminos de montaña conservan su ancho original. Las avenidas anchas se rasterizan con su ancho desde CG; los poblados añadidos tienen una avenida central de cuatro carriles. Las trochas mantienen un carril y las calles habituales, dos.
- Las líneas blancas y amarillas siguen el marco de la cinta original. Las discontinuas se cortan por distancia recorrida; las curvas paralelas no se confunden con cruces. Se omiten veredas que no tienen apoyo lateral.
- Los conectores de poblados usan directamente el limitador original de CG, expuesto como `grade_road_profile`, y el mismo tipo de redondeo acotado. Se conectan a suelo vial apoyado, evitando el lecho bajo un tablero. Los extremos incompatibles con el límite de pendiente se rechazan.

## Validación

`test_native_road_preservation.gd` compara las rutas nativas con las publicadas al juego, verifica la protección de su superficie, los tableros y su colisión, la altura de circulación y los perfiles de carriles. Prueba semillas 42 y 67, con y sin erosión.

`render_native_roads.gd` captura curvas, cambios de pendiente y cuatro carriles, sobre un mapa de resolución 512 con erosión. Las imágenes se guardan en `output/road_review`. El perfil nativo más inclinado de la semilla 67 mide aproximadamente 0,16 m/m.

`render_production_world.gd` comprueba la coincidencia de malla y colisión, las viviendas de las tres regiones y los cruces con agua que existan en la semilla. Un resultado sin muestras de agua no demuestra por sí solo que todos los puentes estén validados. `test_peru_world.gd` comprueba además la circulación y el contacto de ruedas.

La revisión visual de curvas extremas sigue siendo necesaria: estas comprobaciones no convierten automáticamente cualquier solape o recorte visible en un resultado aprobado.

Validación del 10 de noviembre de 2026: `NATIVE_ROAD_PRESERVATION_RESULT 0` en semillas 42 y 67 (59 y 45 rutas nativas), con 352 muestras de vías sobre agua comprobadas. El caso sintético de desniveles fuertes conserva curvas y extremos y limita la pendiente a 0,16. El mapa de producción con erosión pasó `PRODUCTION_WORLD_RESULT 0`; la prueba de circulación pasó `PERU_WORLD_RESULT 0`. Las tres comprobaciones se repitieron después del redondeo final de los conectores, sin errores ni advertencias de ejecución. Se recompiló la extensión Windows incluida en el proyecto.
