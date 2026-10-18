extends SceneTree

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
	var saved_mesh: Mesh = terrain.mesh
	var saved_material: Material = terrain.material_override
	var saved_details := {}
	for detail_name: String in ["AguaGenerada", "PuentesGenerados"]:
		var detail = terrain.get_node_or_null(detail_name)
		if detail != null: saved_details[detail_name] = detail.mesh
	root.add_child(original)
	await process_frame
	var failures := 0
	if terrain.mesh != saved_mesh or terrain.material_override != saved_material:
		push_error("Abrir la escena debe conservar la malla y el material guardados")
		failures += 1
	if terrain.has_node("TerrainWorld/Chunks") or terrain.has_node("Landmarks"):
		push_error("El alcance S11 CG-B no debe ejecutar la integracion S12/S13")
		failures += 1
	if not terrain.terrain_world.is_stub:
		push_error("TerrainWorld debe identificarse como stub de T0")
		failures += 1
	# Explicit preview in memory only. Neither the scene nor its resource is saved.
	terrain.grid_size = 128
	terrain.cell_size = 6.0
	terrain.hydrology_enabled = false
	terrain.preview_roads = false
	terrain.generate_base()
	if terrain.mesh == saved_mesh or terrain.mesh.get_surface_count() != 1:
		failures += 1
	var vertices: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for p: Vector3 in vertices:
		if not is_equal_approx(p.y, terrain.terrain_world.get_height(p.x, p.z)):
			push_error("La vista T0 debe usar el mismo ruido que la API, sin erosion ni caminos")
			failures += 1
			break
	terrain.preview_roads = true
	terrain.generate_base()
	if terrain.last_road_count < 1:
		push_error("La vista T0 con caminos debe producir una red sin ejecutar erosion")
		failures += 1
	terrain.hydrology_enabled = true
	terrain.river_catchment = 2000.0
	terrain.generate_base()
	if not terrain.has_node("AguaGenerada") or (terrain.last_surface.get_bridge_mesh().get_surface_count() > 0 and not terrain.has_node("PuentesGenerados")):
		push_error("La escena debe mostrar agua y cruces elevados")
		failures += 1
	if terrain.terrain_world.get_drainage(0, 0) <= 0:
		push_error("La API debe consultar el drenaje generado")
		failures += 1
	for detail_name: String in ["AguaGenerada", "PuentesGenerados"]:
		var detail = terrain.get_node_or_null(detail_name)
		if detail != null and detail.owner != terrain.owner:
			push_error("Los detalles deben poder guardarse con la escena")
			failures += 1
	terrain.restore_saved_mesh()
	for detail_name: String in ["AguaGenerada", "PuentesGenerados"]:
		var detail = terrain.get_node_or_null(detail_name)
		if saved_details.has(detail_name):
			if detail == null or detail.mesh != saved_details[detail_name]:
				push_error("Restaurar debe conservar los detalles que ya estaban guardados")
				failures += 1
		elif detail != null:
			push_error("Restaurar debe retirar los detalles nuevos")
			failures += 1
	if terrain.mesh != saved_mesh or terrain.material_override != saved_material:
		push_error("Restaurar debe devolver la malla y material originales")
		failures += 1
	print("Escena original S11 CG-B: %d errores" % failures)
	original.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
