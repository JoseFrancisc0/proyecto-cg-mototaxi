# Integración de conductor y vida del mundo — 2026-11-09

Cambios sobre la rama actual, sin crear otra rama.

## Implementado

- Conductor reconstruido con PIFuHD desde la referencia de cuerpo entero, con malla continua de cuerpo y vestimenta, atlas 4K, pesos automáticos y postura sentada con brazos ajustados al manillar. Sustituye el maniquí anterior; el pasajero conserva su propio modelo.
- Opciones para elegir otra foto de referencia, reconstruir localmente una persona de cuerpo entero, revisar en 3D e importar/usar un GLB articulado. Las fotos parciales se conservan como referencia, pero no se completa automáticamente su cuerpo con el método anterior. La generación no utiliza servicios de pago ni envía la imagen. Instalación y límites en `tools/DRIVER_SETUP.md`.
- Seis grabaciones CC0 diferentes de motores pequeños: 125 cc, Gilera 50, tuk-tuk, Derbi 50, Vespa y Piaggio Ape. Capas de ralentí/carga, respuesta al acelerador y volumen de turbo más discreto. Fuentes en `project/audio/engines/recorded/README.md`.
- Clientes en puntos variables de las vías y regateo antes de arrancar: ofertas, contraoferta, rechazo y perfiles de pasajeros.
- Viajes con prisa, bonificación por conducción suave, cambio de destino y parada intermedia que no cobra como entrega final.
- Viviendas y comercios regionales por distrito, con frentes continuos en zonas densas, cimentaciones, escaleras y luces. La integración vial posterior ajusta localmente alturas visuales y físicas; detalles en `MUNDO_PERUANO.md`.
- Tráfico local limitado a seis vehículos y ocho peatones próximos, reciclados al alejarse. Los vehículos siguen rutas y frenan ante un obstáculo; peatones caminan junto a la vía y reaccionan a la bocina.
- Radio con tres señales oficiales en vivo y biblioteca de música propia, memoria de volumen/emisora y reducción durante mensajes; ambiente rural y bocina. Instalación del decodificador y distribución en `MUNDO_PERUANO.md`.
- Cielo, sol e iluminación vinculados al reloj de carrera. En modo libre el ciclo continúa durante la exploración.
- Encuentros peligrosos opcionales, apagados inicialmente: 10 % configurable por encuentro elegible, una tirada por encuentro, enfriamiento guardado, amenazas, margen de ocho segundos, escena de robo y final de jornada. Las zonas ficticias de riesgo no dependen de la región ni del tipo de vivienda. Modo sin muerte activado inicialmente.

## Alcance y límites

El avatar reconstruido sigue estimando la espalda y las partes ocultas. El método anterior de maniquí por piezas quedó retirado por calidad insuficiente. Se comprobó el método nuevo con la referencia de cuerpo entero; el requisito de completar fotos parciales con la misma fidelidad sigue pendiente. Las ventanillas opacas incluidas en algunos modelos de vehículo ocultan parcialmente al conductor. PIFuHD tiene licencia CC BY-NC 4.0 y se utiliza en este proyecto académico; no se afirma permiso comercial irrestricto.

El tráfico y los peatones circulan localmente, sin semáforos sincronizados ni simulación completa de una ciudad. La programación musical, locutores y noticias de las emisoras dependen de sus señales en vivo. Las viviendas y comercios añaden ambientación, sin interiores ni simulación de crecimiento de barrios. No se presenta todo el documento maestro como terminado.

## Controles

- `H`: bocina.
- `B`: encender/apagar radio.
- `N`: siguiente emisora.
- `,` / `.`: volumen de radio.
- Las funciones del mundo y de los pasajeros se pueden configurar en Opciones y se aplican al iniciar la siguiente partida.

## Comprobaciones

- `test_expansion.gd`: partida real, regateo/contraoferta, entrega intermedia, propinas, guardado de enfriamiento, radio, terreno intacto, tráfico/peatones, conductor articulado y robo con restauración al reintentar.
- `test_vehicle_life.gd`: motores distintos, turbo, animación de ruedas, dirección delantera y conducción real.
- `test_jornada.gd`: cuota, ahorros, siguiente día y mapa.
- `test_pregame_ui.gd`: portada, opciones y garaje.
- Generación local PIFuHD completa con la referencia de cuerpo entero y rechazo explícito de fotos parciales para evitar el maniquí anterior. `test_driver_reconstruction.gd` comprueba la malla continua, el atlas 4K y la posición de pelvis/manos en las seis motos; `render_driver_reconstruction.gd` guarda frente, tres cuartos, perfil, espalda y postura sentada.

La prueba heredada `test_escenario.gd` ya presentaba un cierre nativo `C0000005` al terminar antes de estos cambios; no se declara resuelto aquí.
