# Arquitectura regional

76 edificios activos preparados con Blender: 28 en costa y 24 en cada una de sierra y selva y seis familias de barrios por región. Catálogo en `catalog.json`, con región, distritos, ancho de fachada y materiales. La cadena activa es `tools/build_regional_neighborhoods.py`; utiliza los ayudantes geométricos del generador anterior. Los 56 edificios retirados se archivaron fuera del proyecto exportable.

- Costa: autoconstrucción de ladrillo y concreto con azotea, fierros y tanque; fachadas pintadas adosadas, portones, villas y apartamentos modernos.
- Sierra: adobe rural y teja, casas de pueblo, balcones de madera y arcadas coloniales; ladrillo urbano, calamina y vivienda moderna andina.
- Selva: casas urbanas de mampostería con galerías ventiladas, celosías y persianas; villas sombreadas; madera ribereña elevada con palma o calamina y proporciones variadas.

Referencias aportadas por el usuario y contraste con fuentes peruanas: [Miraflores, Perú Travel](https://www.peru.travel/es/experiencias/tour-miraflores-lima), [inventario turístico de Iquitos, Mincetur](https://consultasenlinea.mincetur.gob.pe/fichaInventario/index.aspx?cod_Ficha=291). Son interpretaciones para un mundo ficticio, no réplicas arquitectónicas exactas.

60 superficies fotográficas de Poly Haven se conservan en `materials/`, con autores, CC0 y enlaces en `materials/catalog.json`. Se eligen por función arquitectónica. La dimensión heredada de la API es en milímetros, aunque el campo antiguo se llame `dimensions_cm`; el generador corrige esa conversión. Las pintadas activas son trazos originales de `PeruWallPaint`; los cuatro diseños CC0 de 3DTexel siguen disponibles, sin colocación automática.

Veinte superficies incluyen mapas CC0 originales de normales y ARM, documentados en `materials/pbr_catalog.json`. El generador conecta normales, rugosidad y metalicidad a materiales nativos de glTF. La pintura usa relieve de yeso sin sustituir su color por manchas fotográficas; madera y concreto compartidos mantienen escala métrica.

Ocho edificios de barrio tienen acabados de grafiti basados en las tres imágenes de paredes aportadas por el usuario. Se integran en las caras del muro con UV proporcionales, sin placas añadidas. Procedencia y alcance en `materials/graffiti_references/SOURCE.md`; estas imágenes no se declaran CC0. La galería permite localizar esos edificios mediante **Con grafiti**.

Las 22 fotos reales y las capturas comparativas están en `output/comparacion/`. La revisión incorpora selecciones UV de carpintería de la calle costera y la casona de Iquitos detrás de geometría modelada; fuentes en `reference_details/SOURCE.md`. La fotografía completa del barrio no sustituye el entorno. Referencias adicionales: [Huarán, Estudiolocal](https://estudiolocal.pe/casa-huaran/), [Huayoccari, Barclay & Crousse](https://www.barclaycrousse.com/huayoccari) y [VMT, Swisscontact](https://www.swisscontact.org/es/proyectos/vivienda-progresiva).
