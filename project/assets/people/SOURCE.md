# Peatones regionales

Seis adultos ficticios con referencias originales creadas para el proyecto. Ropa cotidiana de costa, poncho/pollera de sierra y vestimenta cotidiana y cushma amazónica. Se conservan conjuntamente cuerpo, rostro y ropa en una malla articulada; no se pega un retrato a un maniquí.

Reconstrucción local con [PIFuHD de Meta/Facebook Research](https://github.com/facebookresearch/pifuhd), reducción a aproximadamente 24 000 caras y atlas de 2048 píxeles, seguido de articulación y exportación con Blender. Se incluye `PIFUHD_LICENSE.txt`; el código y los pesos usados para reconstruir no se incorporan a los recursos del juego.

`PeruPersonVisual` anima el esqueleto para andar, esperar y llamar con la mano. Los pasajeros y peatones ambientales comparten estos recursos. Las decisiones de los eventos del juego no dependen del aspecto, tono de piel ni vestimenta del personaje.

Herramienta de preparación: `tools/build_peru_people.py`.
