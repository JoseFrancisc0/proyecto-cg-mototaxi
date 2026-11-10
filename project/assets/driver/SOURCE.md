# Conductor reconstruido desde la referencia del usuario

`driver.glb` se reconstruyó con **PIFuHD**, usando la fotografía frontal de cuerpo entero adjuntada por el usuario (`photo.png`). La malla continua procede de la inferencia de normales y ocupación de PIFuHD; no se compone de cilindros o piezas de maniquí. Se extrajo a resolución 512, se optimizó a unas 95 000 caras y se preparó un atlas de 4096×4096. Blender calculó pesos automáticos de articulación y Godot ajusta el asiento y los brazos.

La espalda y las superficies no observadas se estiman. Los dedos y algunas zonas laterales siguen siendo aproximados. El resultado se revisó de frente, tres cuartos, perfil, espalda y sentado. Las fotografías de cara o medio cuerpo todavía no se completan automáticamente con esta misma calidad.

La imagen de referencia es material aportado por el usuario; su inclusión no concede una licencia pública sobre la fotografía ni sobre la identidad representada.

## Herramientas gratuitas y fuentes

- **PIFuHD**: Facebook Research, Shunsuke Saito et al., CVPR 2020. Proyecto y pesos: https://github.com/facebookresearch/pifuhd. Licencia del proyecto CC BY-NC 4.0; componentes PIFu MIT. Texto conservado en `PIFUHD_LICENSE.txt`. Uso en este proyecto académico; no se afirma permiso comercial irrestricto.
- Pesos oficiales: https://dl.fbaipublicfiles.com/pifuhd/checkpoints/pifuhd.pt. SHA-256 comprobado: `891637c65f122c7efe212ebba7ae4581f86d75c92fdd5894096fe32f562175e9`.
- MediaPipe, Google, Apache 2.0: https://github.com/google-ai-edge/mediapipe. Se utiliza para validar el rostro y colocar articulaciones. Detectores y licencia en `models/`.
- Blender, PyTorch, OpenCV, SciPy, scikit-image y Pillow conservan sus respectivas licencias.

Los pesos y dependencias grandes se descargan una vez, permanecen fuera de Git y se ejecutan localmente. No se usan Meshy, cuentas, pagos o créditos; no se envían las fotos a un servidor.

Instalación y reproducción: `tools/DRIVER_SETUP.md`. La herramienta anterior de maniquí quedó retirada del generador.
