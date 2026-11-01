# Conducción y garaje

En **Jugar** se elige una de las seis mototaxis aportadas en Blender. La vista 3D gira automáticamente; arrastrar con el botón izquierdo gira el modelo y la rueda cambia el acercamiento. Las barras usan los mismos valores que la conducción. La selección se aplica al entrar en la partida, también al generar un mundo nuevo.

La selección usa las flechas junto al nombre y el número del vehículo, sin repetir los seis modelos en recuadros inferiores.

## Motores y ruedas

Cada modelo tiene cuatro sonidos propios: ralentí, motor bajo carga, turbo continuo y descarga al soltarlo. Neon Thunder usa un estilo eléctrico/iónico; Faketaxi, deportivo de dos tiempos con flutter; Neon Shadow, diésel pesado con descarga de aire; Silver Guardian, bicilíndrico con compresor mecánico; Midnight Camper, motor suave con turbo silbante; Dusty, monocilíndrico irregular con turbo y metal traqueteante. Los sonidos son síntesis original, sin grabaciones externas; se regeneran con `tools/generate_engine_audio.py`. La herramienta también crea una comparación audible en `output/vehicle_sound_comparison.wav`.

Los modelos exportados incluyen ruedas completas reconstruidas con neumáticos, aros, frenos, bujes y radios. Se evita animar recortes de la carrocería fusionada de los archivos Meshy. La rodadura usa la velocidad con signo y el radio escalado de cada neumático: avanzan, retroceden y se detienen con la moto. Solo el pivote delantero acompaña la dirección; las ruedas traseras mantienen su orientación. Neon Shadow también anima las dos ruedas de su eje trasero adicional. Los ejes se configuran en `tools/vehicle_wheels.json`; los `.blend` originales siguen intactos.

La escala visual y física aumentó un 20 % (longitud aproximada de 3,18 m). Las colisiones, suspensión y centro de masa se ajustan explícitamente sin escalar el cuerpo rígido. El garaje encuadra cada modelo según sus dimensiones y la cámara de conducción se sitúa más cerca. La asistencia de turbo estabiliza el cabeceo siguiendo las normales de contacto para conservar la capacidad de subida con el tamaño mayor.

## Turbo y superficies

- Mantener **Shift** en teclado o **X** en mando, junto con el acelerador, activa el turbo. Dura siete segundos con la reserva llena y se recarga automáticamente al soltarlo. Tras agotarse necesita recuperar el 28 % antes de activarse de nuevo.
- Además de aumentar la potencia y el límite de velocidad, el turbo ayuda a arrancar cuesta arriba cuando al menos dos ruedas están apoyadas. No propulsa el vehículo en el aire. La reserva se muestra en el HUD.
- La tierra reduce velocidad, tracción y estabilidad. La banquina mezcla ambos comportamientos en 1,5 metros; cada rueda consulta su posición. Dusty conserva más capacidad en tierra, pero también pierde velocidad respecto al asfalto.
- El terreno mantiene sus bloques visuales con LOD, con una única superficie física continua. El chasis redondeado reduce los enganches de sus esquinas. Los puentes mantienen su colisión independiente.

## Vehículos

| Modelo | Límite en asfalto | Especialidad |
| --- | ---: | --- |
| Neon Thunder | 78 km/h | Velocidad y turbo |
| Faketaxi Drift | 72 km/h | Agilidad y derrape |
| Neon Shadow | 68 km/h | Equilibrio |
| Silver Guardian | 64 km/h | Agarre y subida |
| Midnight Camper | 60 km/h | Estabilidad |
| Dusty | 62 km/h | Tierra |

Los originales `.blend` no se modifican. `tools/export_vehicles.py` exporta los seis archivos a GLB, normaliza longitud y orientación y limita las texturas a 2048 píxeles. Para repetir la conversión:

```powershell
blender --background --python tools/export_vehicles.py -- "DIRECTORIO_DE_ORIGINALES" "project/assets/vehicles"
```

## Validación

Ejecutar Godot con `--headless --fixed-fps 60 --path project --script res://tests/NOMBRE.gd`:

- `test_mototaxi`: aceleración, frenada, reversa, curvas, vuelco y terreno real.
- `test_vehicle_upgrade`: seis modelos, correspondencia de fichas, resistencia y agarre en tierra, consumo/recarga, arranque con turbo en rampa de 35° y ausencia de propulsión aérea.
- `test_vehicle_life`: sonidos distintos, capas en bucle, respuesta al acelerador, radios importados, giro/reversa/parada de todas las ruedas y dirección exclusivamente delantera, incluida conducción física real.
- `test_driving_surface`: superficie física continua, 36 rayos en antiguas uniones de bloques y reconocimiento de las pistas.
- `test_pregame_ui`: menú y garaje en cinco tamaños de ventana, selección y flujo de carga.
- `test_pregame_start`: entrada real a la partida con Dusty seleccionada.
- `test_drive_routes -- 2 67`: dos viajes con física real; el piloto usa turbo al subir.

`capture_garage.gd` genera vistas de los seis vehículos y del menú estrecho en `output/`.
