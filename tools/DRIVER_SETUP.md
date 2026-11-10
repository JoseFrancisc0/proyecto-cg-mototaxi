# Reconstrucción gratuita del conductor — PIFuHD

El generador actual utiliza **PIFuHD de Facebook Research** para reconstruir una superficie continua del cuerpo y su vestimenta desde una foto. El método anterior que construía un maniquí por piezas quedó retirado. No utiliza Meshy, cuentas, créditos ni servicios de pago. La inferencia es local; las fotos no se envían.

## Uso en este equipo

Ya están instalados los modelos y bibliotecas necesarios. En el juego: **Opciones → Tu conductor → Elegir foto → Transformar foto en personaje 3D → Revisar → Usar este conductor**. El modelo predeterminado se reconstruyó de la imagen de cuerpo entero que adjuntó el usuario.

La reconstrucción completa requiere una persona de cuerpo entero, de frente, con brazos separados, rostro visible y sin objetos que oculten gran parte del cuerpo. Las fotos de cara o medio cuerpo se pueden cargar como referencia, pero la generación actual las rechaza con un mensaje claro: no vuelve a fabricar un cuerpo de baja calidad. **El requisito original de completar cualquier foto parcial con igual fidelidad sigue pendiente.**

## Instalación en otro equipo

Se comprobó en Windows, Blender 5.2/Python 3.13, Node 24 y RTX 4060 de 8 GB. La extracción de superficie usó aproximadamente 2.91 GiB de memoria de tensores GPU en esta prueba; el consumo total del proceso y del sistema es mayor. La instalación de PyTorch ocupa varios GB y los pesos PIFuHD aproximadamente 1.55 GB. Los archivos grandes se excluyen de Git.

Desde la raíz, ajustando la ruta de Blender:

```powershell
& 'D:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe' -m pip install --target tools/.avatar_runtime mediapipe==1.2.2 pillow==13.0.0 opencv-contrib-python==5.0.0.93
& 'D:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe' -m pip install --target tools/.reconstruction_runtime torch==2.8.0 torchvision==0.23.0 --index-url https://download.pytorch.org/whl/cu128
& 'D:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe' -m pip install --target tools/.reconstruction_runtime scikit-image scipy tqdm matplotlib opencv-contrib-python
node tools/download_avatar_models.mjs
node tools/download_human_reconstruction.mjs
& 'D:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe' -m zipfile -e tools/.pifuhd/source.zip tools/.pifuhd
```

Se pueden configurar `DRIVER_BLENDER` y `DRIVER_PYTHON` para otras ubicaciones. El generador detecta las rutas existentes de Blender 5.2. En una exportación hay que distribuir las herramientas como carpeta externa y resolver su ruta; si no están disponibles, se puede importar el GLB ya generado.

```powershell
node tools/create_driver.mjs 'C:/Fotos/persona_cuerpo_entero.png' 'C:/Avatares/persona'
```

## Proceso y revisión

1. MediaPipe detecta una persona, rostro y articulaciones para validar la entrada y colocar el esqueleto.
2. PIFuHD estima normales frontales/posteriores y reconstruye la superficie a resolución 512.
3. Se extienden los colores del borde de la silueta para evitar franjas de fondo en la proyección lateral.
4. Blender combina textura frontal y materiales posteriores estimados en un atlas de 4096×4096. Optimiza a unas 95 000 caras, calcula pesos automáticos y corrige los pocos vértices que quedan sin peso.
5. Godot ajusta pelvis y piernas al asiento y resuelve los brazos hacia el manillar de cada vehículo.

Los resultados intermedios, estado, geometría y GLB se conservan en la carpeta de generación. La malla anterior del jugador solo se reemplaza al pulsar **Usar este conductor**.

La revisión visual incluye frente, tres cuartos, perfil, espalda, primer plano y postura de conducción. Las pruebas funcionales comprueban esqueleto, textura y adaptación del asiento; no sustituyen la revisión visual del parecido.

## Límites y atribución

La espalda, las partes tapadas y la profundidad siguen siendo estimaciones. Los dedos y algunas zonas laterales pueden requerir retoque; la imagen aporta iluminación a la textura. No se promete una reconstrucción exacta desde cualquier foto.

PIFuHD: Facebook Research, CVPR 2020, licencia del proyecto **CC BY-NC 4.0**; incluye componentes PIFu bajo MIT. Esta instalación se usa en el proyecto académico. No se describe como una herramienta con permiso comercial irrestricto. Código/pesos oficiales: https://github.com/facebookresearch/pifuhd. MediaPipe: Google, Apache 2.0. Las demás bibliotecas conservan sus licencias.
