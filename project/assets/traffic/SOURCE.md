# Flota peruana

Cuatro referencias ficticias creadas para este proyecto: hatchback compacto tipo Tico, sedán taxi con franja, cúster y bus urbano. Las fotos aportadas por el usuario sirvieron de referencia visual, no se han incorporado sus marcas de agua ni descargado modelos de pago.

La flota activa se modela con Blender mediante `tools/build_clean_traffic.py`: paneles limpios con pasos de rueda, ventanillas, interior, asientos, marcos, limpiaparabrisas, puertas y livery. Se retiraron las carrocerías reconstruidas con Hunyuan y sus proyecciones fotográficas deformadas. Su licencia se conserva para documentar el trabajo anterior; los originales quedan en la caché de desarrollo, fuera del juego.

Los GLB terminados son los recursos del juego. Los originales de alta resolución y los pesos permanecen en `tools/.worldgen/`, fuera de Git. Las referencias PNG y los ajustes de proyección JSON permiten reconstruir el proceso. La pintura de circulación ofrece variaciones sin cambiar el color de los cristales y matrículas.

Las ruedas están articuladas con pivotes FL/FR/RL/RR y piezas agrupadas por material para reducir llamadas de dibujo. Los JSON conservan dimensiones y ejes en metros. La pintura cambia únicamente los materiales de carrocería, sin teñir cristales, ruedas ni matrículas. Las fotos reales se presentan junto a capturas de Godot en `output/comparacion/index.html`. Es una interpretación de juego, no una réplica fotogramétrica exacta.

Para regenerar la flota activa: Blender en segundo plano con `--python tools/build_clean_traffic.py`. Los scripts de reconstrucción y rig anteriores se conservan como herramientas históricas; no son la cadena activa de estos cuatro vehículos.
