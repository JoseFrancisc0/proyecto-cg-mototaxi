# Interfaz previa al juego

F5 ejecuta `project/main.tscn`. Jugar abre la selección de terreno y semilla; Iniciar entrega el mismo contrato `start_requested({mode, seed, erosion_scale})` a Main. El rediseño no modifica C++, la física ni el terreno guardado.

## Base descargada, no diseñada desde cero

Se compararon Maaack's Menus Template, la plantilla de Chafmere y Racing UI Kit de Ville Seppänen. Se eligió la primera por su escena Godot reutilizable y su distribución de portada: título superior, lista vertical centrada y submenús. Se descartaron las propuestas que se presentaban como generadas con IA.

Base: https://github.com/Maaack/Godot-Menus-Template

La escena original descargada, licencia MIT y commit exacto están en `project/ui/vendor/maaack/`. `project/scenes/pregame_shell.tscn` deriva directamente de esa escena: conserva su jerarquía, título, fondo, lista vertical y pie. Se retiraron dependencias del plugin y se añadió Controles. No se instaló todo el plugin.

La fotografía es la referencia enviada por el usuario, conservada sin dibujar una mototaxi. Su procedencia conocida está en `project/ui/photos/SOURCE.md`. Se quitaron los anteriores scripts de ilustración del taxi y fondo procedural. Se conservaron amarillo, fucsia y Bangers; los botones dicen Jugar, Opciones, Controles, Créditos y Salir. No se añadieron eslóganes ni imitaciones de jerga. El paper aparece en gris discreto al pie y completo en Créditos.

La portada escala a la ventana; los submenús tienen contenido desplazable. Se revisaron 1440×900, 960×640, 720×900, 390×844 y 640×360. La referencia fotográfica tiene resolución limitada: ampliarla no añade detalle real.

## Generación y carga

Terreno guardado reutiliza la escena actual. Nuevo terreno acepta semilla entre 0 y 2147483647 y escalas rápida 0.1, normal 0.35 y completa 1.0. No se alteró la receta del generador.

La carga dedica la pantalla a la vista real de TerrainMesh: consulta preview_serial y convierte el RGB recibido de C++ en una textura de 768×432. Conserva el último cuadro mientras finaliza. No usa un paisaje simulado ni inventa un tiempo restante. Muestra la etapa real, porcentaje monotónico y tiempo transcurrido. La ruta guardada puede no emitir capturas nuevas de erosión.

## Música

La pista predeterminada es el enganchado elegido por el usuario: Cumbieton vs Reggaeton Old School (2020), DJ Pirata, Maxi Gen, El Kaio y DJ Juanchii. Se descargó el MP3 desde el enlace MediaFire publicado por DJ Juanchii en la descripción de https://www.youtube.com/watch?v=_vwVLdle08M. Se conserva el archivo completo sin recortes. Fuente y condiciones conocidas en `project/audio/DJ_JUANCHII_SOURCE.md`. La anterior No Frills Cumbia se conserva como recurso alternativo con su licencia CC BY 4.0.

Opciones permite elegir un MP3, OGG o WAV local. Solo se guarda la ruta en `user://pregame_audio.cfg`, no se copia ni publica el archivo. Se puede restaurar la pista incluida, ajustar volumen y activar sonido saturado: efecto Overdrive en un bus exclusivo del menú, retirado al terminar. El silencio permanece disponible durante la carga. La música se desvanece al entrar a jugar.

## Verificación

- `test_pregame_ui.gd`: semilla, escala, doble arranque, progreso, reintento, ayuda, audio y distribución dentro de cinco ventanas.
- `test_pregame_failure.gd`: dos fallos simulados; conserva la pausa y permite reintentar. Los mensajes de error de generación son intencionales.
- `test_pregame_start.gd`: terreno temporal pequeño, entrada real a partida, HUD y cierre de carga.
- `capture_pregame_ui.gd`: capturas reales en `output/ui_review/`, incluyendo opciones y tamaños estrechos.
- `capture_loading_live.gd`: terreno temporal de 256 celdas con erosión; se comprobaron ocho imágenes distintas durante la generación, sin modificar la escena guardada.

Las capturas se renderizan con Compatibility y audio Dummy. No se probó auditivamente la pista local del usuario ni el selector nativo mediante interacción manual; sí se verifica la carga del archivo y los controles de audio por código.
