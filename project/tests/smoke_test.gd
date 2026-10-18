extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _initialize() -> void:
	var terrain := TerrainNoise.new()
	terrain.set_seed(68)
	var original: float = terrain.get_height(23.5, -17.0)
	terrain.set_seed(99)
	terrain.set_seed(68)
	check(is_equal_approx(original, terrain.get_height(23.5, -17.0)), "La semilla debe reproducir las alturas")
	var roads := RoadNetwork.new()
	roads.generate_roads(terrain, 32, 1.0, {"num_points": 0})
	check(roads.get_road_count() == 0, "Caminos desactivados")
	var builder := TerrainMesh.new()
	var generated := builder.generate_mesh(terrain, roads, 32, 1.0, {"erosion_enabled": false})
	check(generated != null, "La extension debe generar una malla")
	if generated != null:
		var arrays := generated.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_VERTEX].size() == 33 * 33, "Cantidad de vertices")
		check(arrays[Mesh.ARRAY_INDEX].size() == 32 * 32 * 6, "Cantidad de indices")
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			check(vertex.is_finite(), "Altura finita")
	var eroded := builder.generate_mesh(terrain, roads, 8, 1.0, {
		"erosion_enabled": true, "erosion_fluvial": 2,
		"erosion_thermal": 2, "erosion_deposition": 2, "erosion_levels": 0,
	})
	check(eroded != null, "Erosion de prueba")
	if eroded != null:
		for vertex: Vector3 in eroded.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			check(vertex.is_finite(), "La erosion debe producir alturas finitas")
	var scene := load("res://terrain_demo.tscn") as PackedScene
	check(scene != null, "La escena debe cargar")
	if scene != null:
		var instance := scene.instantiate()
		check(instance.get_node("Terrain").has_method("generate_base"), "El script del terreno debe compilar")
		instance.free()
	print("Revision basica: %d errores" % failures)
	quit(0 if failures == 0 else 1)
