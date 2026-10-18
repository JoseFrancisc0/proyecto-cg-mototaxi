extends SceneTree

var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var data := TerrainField.new()
	var cfg := {"levels": 0, "iteration_scale": 0.001, "retarget_iterations": 10}
	check(data.generate(68, 64, 1.0, cfg), "Generacion C++")
	check(data.get_heights().size() == 65 * 65, "Muestras del heightfield")
	for h: float in data.get_heights():
		check(is_finite(h), "Alturas finitas")
	for x in range(-32, 33, 4):
		var b := data.get_biome(x, 0)
		check(is_equal_approx(b.x + b.y + b.z, 1.0), "Pesos normalizados")
	check(data.get_biome(-32, 0).x > 0.9, "Costa al oeste")
	check(data.get_biome(32, 0).z > 0.9, "Selva al este")
	var regional := data.get_regional_maps()
	check(regional.hardness.size() == 65 * 65, "Mapa de dureza publicado")
	for hardness: float in regional.hardness:
		check(hardness >= 0 and hardness <= 1, "Dureza en [0,1]")
	for talus: float in regional.talus:
		check(talus > 0, "Pendiente critica positiva")
	var left := data.get_chunk_heights(0, 0, 32)
	var right := data.get_chunk_heights(32, 0, 32)
	for z in range(33):
		check(left[z * 33 + 32] == right[z * 33], "Borde compartido sin grietas")
	var route := data.find_route(Vector3(-20, 0, -20), Vector3(20, 0, 20))
	check(route.size() > 2, "A* devuelve una ruta")
	for p: Vector3 in route:
		check(is_equal_approx(p.y, data.get_height(p.x, p.z)), "Ruta sobre alturas finales")
	var duplicate := TerrainField.new()
	duplicate.generate(68, 64, 1.0, cfg)
	check(duplicate.get_heights() == data.get_heights(), "Reproducibilidad del pipeline")
	check(not duplicate.generate(68, 63, 1.0, cfg), "Rechaza resoluciones incompatibles")
	var eroded := TerrainField.new()
	var retargeted := TerrainField.new()
	eroded.generate(68, 64, 1.0, {"levels": 0, "iteration_scale": 0.001, "retarget_enabled": false, "roads_enabled": false})
	retargeted.generate(68, 64, 1.0, {"levels": 0, "iteration_scale": 0.001, "retarget_enabled": true, "retarget_iterations": 10, "roads_enabled": false})
	var original := eroded.get_initial_heights()
	var constraints := 0
	for z in range(65):
		for x in range(65):
			if eroded.get_drainage(x - 32, z - 32) < 1.05 and eroded.get_biome(x - 32, z - 32).y > 0.45:
				constraints += 1
				check(absf(retargeted.get_height(x - 32, z - 32) - original[z * 65 + x]) < 0.0001, "Retargeting conserva sus restricciones")
	check(constraints > 0, "La prueba debe incluir crestas restringidas")
	var world := TerrainWorld.new()
	world.grid_cells = 64
	world.chunk_cells = 32
	world.cell_size = 0.75
	world.iteration_scale = 0.001
	root.add_child(world)
	world.generate(68)
	var success: bool = await world.generation_finished
	check(success, "Integracion de TerrainWorld")
	check(world.get_node("Chunks").get_child_count() == 4, "Cuatro chunks")
	await physics_frame
	await physics_frame
	for sample: Vector2 in [Vector2(-20.25, 3.75), Vector2(0, 0), Vector2(12.75, -14.25), Vector2(3.24, 5.37)]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(sample.x, 200, sample.y), Vector3(sample.x, -200, sample.y))
		var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty(), "Colision del heightmap")
		if not hit.is_empty():
			check(absf(hit.position.y - world.get_height(sample.x, sample.y)) < 0.1, "Colision alineada con las alturas")
	world.queue_free()
	await process_frame
	print("TerrainWorld: %d errores" % failures)
	quit(0 if failures == 0 else 1)
