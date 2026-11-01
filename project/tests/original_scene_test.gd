extends SceneTree
## Escena original terrain_demo.tscn con el formato actual (desde el 2026-10-21 la escena
## guarda solo la configuracion y el suelo, no la malla): abrir la rehace, los botones
## generan vistas en memoria, el agua sale en el shader (S14) o como malla, y restaurar
## vuelve a la configuracion y al suelo guardados.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load("res://terrain_demo.tscn") as PackedScene
	var original := scene.instantiate()
	var terrain = original.get_node("Terrain")
	if not terrain.has_method("generate_base"):
		push_error("El script del terreno no compila")
		original.free()
		quit(1)
		return
	var saved_ground: PackedByteArray = terrain.ground_bytes
	var saved_seed: int = terrain.noise_seed
	root.add_child(original)
	await process_frame
	var failures := 0
	if saved_ground.is_empty() or terrain.mesh == null or not (terrain.material_override is ShaderMaterial):
		push_error("Abrir la escena debe rehacer la malla y el material desde el suelo guardado")
		failures += 1
	if terrain.ground_bytes != saved_ground:
		push_error("Abrir la escena no debe cambiar el suelo guardado")
		failures += 1
	if not terrain.terrain_world.is_stub:
		push_error("TerrainWorld debe identificarse como stub de T0")
		failures += 1
	# Vista en memoria (la escena no se guarda).
	terrain.vegetation_enabled = false
	terrain.grid_size = 128
	terrain.cell_size = 6.0
	terrain.hydrology_enabled = false
	terrain.preview_roads = false
	terrain.generate_base()
	if terrain.mesh == null or terrain.mesh.get_surface_count() != 1:
		failures += 1
	var vertices: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for p: Vector3 in vertices:
		if absf(p.y - terrain.terrain_world.get_height(p.x, p.z)) > 1e-3:
			push_error("La vista T0 debe usar el mismo ruido que la API, sin erosion ni caminos")
			failures += 1
			break
	terrain.preview_roads = true
	terrain.generate_base()
	if terrain.last_road_count < 1:
		push_error("La vista T0 con caminos debe producir una red sin ejecutar erosion")
		failures += 1
	# Agua (S14): por defecto en el shader (mapa de rios), sin la malla de cintas.
	terrain.hydrology_enabled = true
	terrain.river_catchment = 2000.0
	terrain.water_style = 0
	terrain.generate_base()
	var mat := terrain.material_override as ShaderMaterial
	if mat == null or not mat.get_shader_parameter("rivers_enabled") or not (mat.get_shader_parameter("river_map") is ImageTexture):
		push_error("Con agua en el shader, el material debe recibir el mapa de rios")
		failures += 1
	if terrain.has_node("AguaGenerada"):
		push_error("Con agua en el shader no debe haber malla de agua")
		failures += 1
	terrain.water_style = 1
	terrain.generate_base()
	if not terrain.has_node("AguaGenerada") or (terrain.last_surface.get_bridge_mesh().get_surface_count() > 0 and not terrain.has_node("PuentesGenerados")):
		push_error("Con la malla anterior, la escena debe mostrar agua y cruces elevados")
		failures += 1
	if terrain.terrain_world.get_drainage(0, 0) <= 0:
		push_error("La API debe consultar el drenaje generado")
		failures += 1
	for detail_name: String in ["AguaGenerada", "PuentesGenerados"]:
		var detail = terrain.get_node_or_null(detail_name)
		if detail != null and detail.owner != null:
			push_error("Los detalles no se guardan en la escena (se rehacen al abrirla)")
			failures += 1
	terrain.water_style = 0
	terrain.noise_seed = 12345
	terrain.restore_saved_mesh()
	if terrain.ground_bytes != saved_ground or terrain.noise_seed != saved_seed:
		push_error("Restaurar debe devolver la configuracion y el suelo guardados")
		failures += 1
	if terrain.mesh == null or not (terrain.material_override is ShaderMaterial):
		push_error("Restaurar debe rehacer la malla con texturas")
		failures += 1
	print("Escena original S11 CG-B: %d errores" % failures)
	original.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
