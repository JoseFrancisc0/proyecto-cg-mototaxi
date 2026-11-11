# Referencias reales y revisión visual

Abrir `output/comparacion/index.html`. Contiene 18 familias de barrios y cuatro vehículos, con una fotografía real junto a una captura de Godot y la fuente original. Las escenas de muestra permiten comparar los recursos con una cámara próxima a la referencia; se identifican por separado las capturas del mapa completo. No se afirma una reconstrucción fotogramétrica exacta.

## Recursos activos

- 76 viviendas: 28 en costa y 24 en cada una de sierra y selva. Costa: ladera, popular, Barranco/tradicional, residencial, moderna y rural. Sierra: urbana, San Blas/tradicional, valle residencial, contemporánea, adobe rural y ladera. Selva: popular urbana, Iquitos tradicional, residencial, contemporánea tropical, comunidad rural y ribereña.
- Biblioteca de 60 superficies fotográficas originales de Poly Haven, 20 por región. Se eligen por función arquitectónica; no se fuerza su uso para cumplir una cantidad. Autores y CC0 en `project/assets/houses/peru/materials/catalog.json`. El nombre heredado `dimensions_cm` contiene los milímetros de la API; el generador convierte correctamente a metros.
- Las pintadas activas son trazos de pintura sobre el muro, con capas y goteos, sin el logotipo rectangular anterior. Los cuatro diseños CC0 descargados se conservan como biblioteca, pero ya no se colocan automáticamente. La basura se agrupa en pocos puntos, con bolsas, cartones, papeles y botellas de formas diferentes.
- Cuatro carrocerías nuevas modeladas en Blender, con paneles, cristales, interior y llantas independientes. No utilizan las proyecciones fotográficas deformadas de la versión anterior.

## Terreno y regiones

Se parte del suelo erosionado anterior a los cortes viales nativos, y se aplica una sola integración compartida de ríos, calles y colisión. La calzada tiene prioridad sobre los hombros de otras vías cercanas. Los bloques mantienen la misma altura visual y física, con faldones de profundidad fija.

Las regiones tienen sectores más amplios y transiciones menos abruptas. Se buscan emplazamientos con suelo apto para poblados conectados en las tres regiones, con cuadrantes de barrios distintos, manteniendo los cauces. La costa también incorpora viviendas de ladera con escaleras. Los barrios nuevos no se instalan encima de vías existentes.

Los cruces de agua conservan al menos 1,2 m de altura en la prueba de producción. La detección física de agua usa los mismos triángulos y la misma interpolación que la superficie dibujada, incluidas las orillas junto a vértices secos. La nivelación de terrenos próximos conserva un margen respecto al nivel potencial del agua.

## Regeneración de recursos y galería

1. `tools/download_regional_materials.py`: prepara la biblioteca de superficies, con sus fuentes.
2. Blender con `--python tools/build_regional_neighborhoods.py`: viviendas y catálogo. Acepta estilos tras `--` para regenerar un grupo concreto sin sustituir el resto.
3. Blender con `--python tools/build_clean_traffic.py`: cuatro vehículos activos.
4. Pintadas activas: `project/scripts/peru_wall_paint.gd`. `tools/download_graffiti.py` conserva la biblioteca anterior, sin forzar su colocación.
5. `tools/prepare_comparison_references.py`: fotos reales de la galería; las imágenes del usuario ya están copiadas a `output/comparacion/referencias/` en esta máquina.
6. Godot: `render_neighborhood_catalog.gd`, `render_peru_assets.gd` y `render_production_world.gd`, en `project/tests/`.
7. `tools/build_comparison_gallery.py`: galería, comprobación de 72 modelos, 60 texturas únicas y enlaces locales a las fotos.

`output/` y las cachés de desarrollo permanecen fuera de Git. Los recursos activos del juego están en `project/assets/`. Las fotos aportadas por el usuario pueden ser necesarias al regenerar la galería desde otra máquina.

## Revisión de parecido del 10 de noviembre de 2026

La revisión editorial está en `docs/revision_visual.json` y se muestra en cada comparación. Ninguna tarjeta se aprueba automáticamente por el número de modelos, texturas o pruebas físicas. Las etiquetas «Por mal camino», «Avance parcial» y «Sin aprobar» indican qué queda por reconstruir respecto a la fotografía. No se declara alcanzado un resultado casi idéntico.

La tienda amarilla costera y la casona de Iquitos tienen una construcción específica basada en sus fotos: distribución de vanos, colores, molduras, arcos y carpintería. Se seleccionan detalles fotográficos de puertas, postigos y vitrinas mediante UV detrás de los marcos y rejas 3D. Las fotografías fuente están en `project/assets/houses/peru/reference_details/`; el entorno entero no se proyecta como un plano. `tools/reference_facades.py` contiene las proporciones y selecciones UV. La cal y la carpintería de San Blas se acompañan de rejas romboidales y una muestra de calle estrecha con desnivel.

`tools/regional_facade_components.py` añade fachadas posteriores y laterales expuestas, siete construcciones de ventana, cinco accesos y cuatro balcones con retornos cerrados. `tools/repair_gltf_paint.py` conserva explícitamente la pintura en `baseColorFactor`: el exportador estaba perdiendo el color. `tools/audit_regional_assets.py` verifica los factores exportados y los cuatro pivotes de rueda de cada vehículo.

Los puentes comparten el material completo del terreno, incluida su iluminación; igualar sólo el color del asfalto no corregía el parche gris. Los tableros estructurales quedan debajo del pavimento. Se seleccionan vigas, arco, celosía y atirantado según luz y región. Las vistas de ambos laterales y la trasera de los vehículos permiten revisar cierres de carrocería.

## Comparación interactiva y conjuntos de costa

El menú principal incluye **Comparar barrios**: las 18 familias y los cuatro vehículos, con referencia a la izquierda y conjunto 3D a la derecha. Arrastrar gira la cámara, la rueda acerca y el botón derecho desplaza. Las dos vistas conservan la proporción de la fotografía. El visor carga las notas de revisión y declara que el parecido no está aprobado como casi idéntico. `tools/prepare_reference_viewer.py` copia las fotos sin alterar sus píxeles y reconoce el formato real para evitar importaciones fallidas por extensiones incorrectas.

`PeruReferenceBlocks` construye muestras completas de VMT, Quinta Miraflores y Costa Verde con los mismos modelos utilizados en la partida. Usa MultiMesh por pieza compartida, una cuadrícula de lotes para ajustar el terreno y fotografías guardadas con sus fuentes en `project/assets/reference_photos/`. La muestra de ladera tiene calles curvas y viviendas a ambos lados sobre un cerro árido. La de malecón incorpora oficinas verdes escalonadas, torres residenciales diferentes, acantilado, paseo y vía inferior. Estas composiciones controladas se distinguen de las capturas del mapa procedural: la generación de una partida mantiene su propia distribución.

`tools/coastal_reference_buildings.py` sustituye las cuatro villas y cuatro edificios anteriores. Las casas de Quinta tienen ala baja, cubiertas detrás del frontón ondulado y cercos de ladrillo y balaustres. Las torres distinguen apartamentos curvos, terrazas de enchape, una torre blanca esbelta y oficinas verdes con retranqueos. No se aplica el mismo balcón a todas las tipologías. Los recursos están integrados en el catálogo y se colocan según distrito.

Las muestras de los cuatro puentes se generan con `render_bridge_catalog.gd`. La interfaz se comprueba con `render_reference_viewer.gd`, que captura los casos específicos de las tres regiones y un vehículo, y comprueba selección de foto y zoom. `test_reference_navigation.gd` comprueba abrir el visor desde el menú y regresar. Las capturas individuales de casas y vehículos y las capturas del mapa deben regenerarse después de cambiar recursos.

`tools/andes_amazon_reference_buildings.py` reconstruye cuatro familias adicionales: la vivienda de piedra con cuerpos de madera y cubierta asimétrica de Huayoccari, muros de patio y casas de adobe, habitaciones bajas de colores de Tarapoto y la casa tropical de planta blanca y galería superior de madera. Se separan los vidrios oscuros de las cortinas, y se usan materiales calibrados por color de referencia. El generador comprueba que no quede geometría a más de 30 cm bajo la base; esto detecta piezas mal orientadas que deformarían la escala o harían flotar la casa.

Las composiciones usan materiales con UV en metros, vegetación con datos de luz de instancia y flores agrupadas por malla. El generador de viviendas descarta un modelo que no encaja antes de probar otro, para que una torre grande no bloquee la variedad de una calle. El nuevo poblado costero se nivela con una pendiente más suave antes de crear la malla y la colisión.

`tools/download_regional_pbr.py` conserva los mapas originales CC0 de normales y ARM de veinte materiales de Poly Haven, con sus enlaces en `materials/pbr_catalog.json`. Las normales aportan relieve; los canales verde y azul del ARM controlan rugosidad y metalicidad. No se simula el relieve usando el color de una foto como altura. La pintura mantiene su color y recibe una normal de yeso suave. Los elementos compartidos de madera y concreto usan también esta biblioteca, y la madera de Huayoccari tiene veta real a escala métrica.

`tools/share_gltf_textures.py` extrae los bytes originales de las imágenes incrustadas y los deduplica por SHA-256 en `shared_textures/`. Los GLB conservan su geometría y referencian esas imágenes mediante URI relativas válidas de glTF. Se reconstruyen las vistas de búfer y las referencias de los accesores, sin cambiar resolución, compresión ni píxeles. El exportador aplica este paso en cada generación; el catálogo y sus rutas de modelo permanecen estables.
