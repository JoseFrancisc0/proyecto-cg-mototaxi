# Renovación del mundo peruano

## Recursos y ambientación

Se sustituyó la circulación de cajas por cuatro carrocerías reconstruidas localmente: compacto, sedán, cúster y bus. Hay variaciones de pintura y dimensiones en metros. Se sustituyeron los peatones ambientales y pasajeros genéricos por seis personajes reconstruidos con ropa completa y esqueleto animado.

El catálogo activo contiene 72 variantes: 24 por región. La selección depende de región y distrito (popular, tradicional, residencial, moderno o rural; ribereño en la selva). Los barrios densos comparten frentes casi contiguos; las villas tienen retiro y vegetación. Hay ladrillo sin tarrajear, fachadas pintadas, adobe, balcones coloniales, galerías ventiladas, viviendas amazónicas urbanas y casas de madera con distintos techos. Los barrios populares añaden grafiti y desperdicios; los residenciales, jardineras. No hay interiores.

Los pisos y zócalos se apoyan en la superficie muestreada; las casas elevadas prolongan sus apoyos hasta el suelo. Los comercios usan las fachadas de las viviendas y hay iluminación junto a vías urbanas. Las extensiones antiguas de casas flotantes y locales independientes de cajas se retiraron de la instalación del mundo.

## Circulación y superficies

`PeruRoadLayout` dibuja superficies continuas y proporciona perfiles de uno, dos, tres y cuatro carriles según el tipo de vía y el espacio disponible. Las avenidas que no caben en una ladera conservan dos carriles. Las calles y avenidas de sentido único tienen enlaces dirigidos; los peatones pueden caminar en ambos sentidos. No hay semáforos sincronizados ni una simulación completa de intersecciones urbanas.

Los vehículos eligen enlaces de salida, guardan distancia y excluyen el terreno y las calzadas de la detección frontal de obstáculos. Los actores bloqueados se recuperan fuera de la cercanía del jugador. Las vías urbanas tienen veredas sólidas; los peatones utilizan trayectos completos comprobados sobre ellas o sobre suelo caminable, con regreso por el mismo lado al finalizar el recorrido. Se comprueban pendientes, escalones, agua y viviendas antes de crear la ruta. El tráfico y los peatones se suspenden con la pausa.

Las carreteras normales se pintan sobre la misma malla del terreno: no reciben una segunda calzada superpuesta ni perforaciones del material. La nivelación compartida ajusta visuales y colisión, con encuentros promediados y hombros suaves. Los vértices de los bloques y sus niveles de detalle usan las alturas finales. Las veredas se recortan contra los corredores de circulación, incluidos cruces y curvas. Solo los puentes tienen tablero independiente. La vegetación se retira del ancho nuevo y su densidad depende del distrito. Se conservan conducción fuera de pista, turbo y obstáculos.

Las cuatro carrocerías tienen ruedas independientes con giro y dirección delantera. Cuatro sondeos de contacto ajustan inclinación y suspensión sobre la superficie física. Hay luces nocturnas, luces de freno, iluminación del asfalto, bocinas al bloquearles el paso y cuatro reclamos con voz sintetizada localmente. Las carrocerías conservan un acabado estilizado; no se presentan como escaneos fotográficos exactos.

## Agua y puentes

Los cauces parten de la hidrología existente y modifican localmente su lecho. Ríos y lagos usan polígonos recortados contra cada triángulo del terreno, con una sola superficie de agua y colores regionales. Los pasos sobre agua conservan un tablero sólido con barandas, apoyos y variantes de celosía o arco; no se rellena el cauce para simular el puente. El océano cubre el exterior de los cuatro bordes. El límite jugable continúa existiendo; no se añadió navegación marítima.

## Radio

Tres señales oficiales en vivo: [Nueva Q](https://www.radionuevaq.pe/qa-crp/radioenvivo/on-demand/), [Radiomar](https://www.radiomar.pe/qa-crp/radioenvivo/on-demand/) y [La Inolvidable en Oigo](https://www.oigo.com/lainolvidable/radioenvivo/). Requieren internet. Una cuarta opción reproduce archivos MP3/OGG/WAV propios en `user://radio/`. No se incluyen grabaciones descargadas de canciones ni se mantienen las pistas instrumentales generadas como emisoras.

En un checkout nuevo ejecutar `python tools/install_radio_runtime.py`. Instala el decodificador gratuito FFmpeg mediante imageio-ffmpeg en `tools/.radio_runtime`, excluido de Git. Esta copia ya tiene el decodificador instalado. Para distribuir una exportación de Windows, incluir FFmpeg como archivo externo en `project/bin/media/ffmpeg.exe` (junto a sus avisos/licencia y fuera del PCK). Conservar las condiciones de distribución de la compilación elegida; no se paga ningún servicio de generación. Las señales pueden cambiar de dirección o dejar de estar disponibles.

## Comprobación

- `test_peru_world.gd`: generación, perfiles, grafo, terreno visual/físico, veredas fuera de los cruces, selección regional de casas, sentidos únicos y un minuto de tráfico/peatones; comprueba cuatro ruedas, contacto, luces y bocina/voz.
- `test_peru_geometry.gd`: vigas sin deformación por escala global y despeje de árboles cuyo tronco está desplazado respecto al origen de su modelo.
- `test_expansion.gd`: integración con viajes, regateo, propinas, guardado, radio, conductor personalizado y recuperación tras el evento de robo.
- `test_live_radio.gd`: recepción de audio real, amplitud y cierre del decodificador.
- `render_peru_assets.gd`: capturas de las cuatro carrocerías, 72 edificios y seis peatones.
- `render_district_streets.gd`: calles regionales y tráfico nocturno con iluminación del suelo.
- `render_peru_world.gd`: vistas regionales y de cauce dentro de un mapa generado.

Los pesos de reconstrucción, cachés, mallas originales y capturas de comprobación quedan fuera de Git. El juego utiliza únicamente los GLB y texturas terminados. No se utilizaron servicios Meshy/Tripo de pago para esta renovación. Atribuciones y licencias de las herramientas se conservan junto a los recursos.

La revisión posterior con fotos reales, 60 materiales fotográficos y poblados regionales está documentada en COMPARACION_REFERENCIAS.md.
