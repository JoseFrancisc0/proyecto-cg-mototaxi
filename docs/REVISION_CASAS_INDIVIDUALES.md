# Casas individuales, envolventes y accesos

El menú **Revisar casas** muestra los 76 modelos activos, aislados, con botones para frente, izquierda, derecha, espalda y cubierta. La galería equivalente está en `output/house_integrity/index.html`. Las imágenes son renders de los mismos recursos utilizados en la partida. Se distinguen las comprobaciones geométricas del juicio de parecido: ningún resultado se presenta como réplica casi idéntica aprobada.

## Cambios de construcción

- `house_envelope.py` comprueba el cruce entre puertas de planta baja y ventanas antes de exportar, registra el acceso y da espesor y cantos a los paneles abiertos. La auditoría posterior lee los triángulos reales de cada GLB, suelda posiciones coincidentes para el análisis y busca bordes sin cerrar.
- Se corrigió la actualización de transformaciones al colocar ventanas laterales y traseras: leer matrices pendientes podía dejar elementos en posiciones incorrectas.
- Las ventanas de planta baja reservan un espacio independiente para la puerta. Se retiró el cristal panorámico que tapaba puertas y marcos en los modelos andinos anteriores.
- Los balcones y terrazas tienen retornos y cierres intermedios; los miradores de madera cierran sus costados. Las barandas se construyen agrupadas en una malla para evitar miles de operaciones separadas. Los jardines de Quinta tienen retornos laterales.
- La revisión lateral detectó y retiró un balcón de San Blas que se añadía incluso cuando no existía segunda planta. Las columnas y vigas de cubiertas tropicales terminan a la cota real de su faldón. Las viviendas elevadas incorporan piso de galería, apoyos delanteros y protección continua, dejando sólo el acceso alineado con su escalera.
- Los muretes residenciales añadidos automáticamente se retiraron. Los cercos pertenecen al modelo; las jardineras sueltas se ajustan al suelo y se excluyen de calzadas y agua.

## Apoyo y acceso en el mapa

La colocación consulta el acceso real del modelo, incluida la aproximación a escaleras incorporadas en casas elevadas. Los lotes normales aceptan hasta 85 cm de variación; los de ladera, hasta 1,20 m. Las cimentaciones visibles siguen la altura del terreno a lo largo de su perímetro, en vez de usar un pedestal alto de altura uniforme.

`PeruHouseAccess` rechaza recorridos individuales de más de 9 m, desniveles sin espacio para huellas, contrahuellas mayores de 18 cm y apoyos excesivamente separados del suelo. Añade descansos entre vuelos de doce peldaños. Las viviendas de ladera ya no reciben escaleras rectas de hasta 28 m de desnivel desde el centro de la carretera. Los poblados nativos y añadidos se nivelan antes de construir malla, colisión y viviendas.

La integración del terreno aplica la prioridad de las carreteras después de nivelar poblados. Cambiar sólo las parcelas podía introducir un cambio brusco de pendiente bajo un bus al salir del poblado; la comprobación de contacto de ruedas detectó ese caso y se corrigió el orden.

Las calles urbanas incorporan un área de lote nivelada que sigue su perfil, manteniendo la calzada como referencia. La búsqueda de poblado andino admite terrenos montañosos que se puedan aterrazar y conectar; exigir el mismo emplazamiento casi plano de la costa dejaba la sierra sin viviendas válidas.

## Estudios individuales

Las cuatro fotos del usuario originan cuatro casas nuevas: portón de madera, vivienda angosta con balcón, casa tropical blanca y vivienda contemporánea de esquina. Se guarda la ubicación como no verificada; no se atribuyen esas imágenes a un distrito sin evidencia. La madera fina de carpintería es un material original horneado en Blender, separado de las texturas CC0 de madera envejecida.

Las cuatro viviendas contemporáneas andinas se reconstruyeron usando proyectos individuales de Reactivo: [Kinsawasi](https://reactivoarq.com/en/kinsawasi), [Larapa](https://reactivoarq.com/en/larapa), [Zarumilla](https://reactivoarq.com/en/zarumilla) y [Enaco](https://reactivoarq.com/en/enaco). También se conservan fuentes de casas de la selva, vivienda rural y autoconstrucción, con su estado de investigación en `project/assets/house_studies/catalog.json`. Una fuente localizada no implica un modelo equivalente ya terminado. Casa Sucre y Casa Azul se clasifican en Barranco, costa, de acuerdo con sus autores.

Las referencias de tipo compartidas por varias variantes se indican como tales. Los modelos sin referencia individual adecuada quedan identificados como pendientes, sin sustituir la foto por una imagen general de barrio.

## Comprobaciones

`tools/audit_house_envelopes.py` inspecciona la geometría exportada; `test_house_integrity.gd` prueba rechazos de escaleras imposibles y los accesos de un mapa generado; `render_house_integrity.gd` genera cinco ángulos por modelo. `render_production_world.gd` comprueba además las tres regiones, el margen del agua y la coincidencia entre suelo visible y físico. Las capturas de muestra sobre suelo plano y las capturas de partida se mantienen separadas.

Validación final del 10 de noviembre de 2026: 76 modelos sin bordes abiertos en la auditoría; `HOUSE_INTEGRITY_RESULT 0`, `PERU_WORLD_RESULT 0`, `REFERENCE_NAVIGATION_RESULT 0` y `PRODUCTION_WORLD_RESULT 0`. El mapa de producción, semilla 67 y resolución 512, contiene viviendas en las tres regiones y mantiene 1,645 m de margen mínimo en los cruces de agua muestreados. Estos controles no sustituyen la revisión artística de parecido.

El exportador publica cada GLB terminado de forma atómica desde una carpeta de trabajo externa al directorio importable. Así el editor no ve las fases intermedias con imágenes incrustadas ni importa un archivo a medio reescribir.

## Pulido de fachadas, rejillas y pintadas

Las rejillas de San Blas se construyen a partir de los puntos y medidas de las ventanas reales. Los rombos se recortan dentro de su marco; la distribución independiente anterior invadía el hueco de la puerta. Las ventanas son más esbeltas y la carpintería superior de Huayoccari sigue el perfil inclinado de su cubierta.

Se cierran los tramos entre portones y muros de las dos viviendas modernas señaladas, incluidos los retornos de esquina. La celosía de la casa de esquina tiene un volumen cerrado detrás, y sus lamas conectan piso y dintel.

Ocho modelos de barrio incorporan las tres imágenes de paredes con grafitis aportadas por el usuario. Se asignan a caras de la propia mampostería, con selección UV a escala proporcional y sin añadir placas delante de la casa. Cuatro acabados se ven de frente y otros cuatro en medianeras expuestas. Las pintadas geométricas de los modelos restantes se colocan respecto al muro real, no respecto al vuelo del tejado. La galería añade el filtro **Con grafiti** y distingue referencias de acabado de las fotos de edificios completos.

La lectura de las fuentes JSON de la galería usa UTF-8 explícito para evitar textos como «jardÃ­n». Las fotos originales de paredes se conservan sin modificar, con su procedencia en `materials/graffiti_references/SOURCE.md`.

## Cierres de las cuatro viviendas tropicales

Las variantes `selva_tropical_actual_0` a `_3` incorporan puertas en las habitaciones de la galería y cierres continuos hasta la cubierta, con cielos y remates adaptados a los techos inclinados. Los muros de acceso de las variantes 0 y 2 alcanzan las jambas del portón y retornan por los costados hasta la vivienda. Se conserva la veranda abierta sobre su baranda perimetral, como en la referencia.

Se regeneraron y revisaron las cinco vistas de cada variante. La auditoría de las cuatro mallas exportadas no encuentra bordes abiertos y conserva sus entradas.
