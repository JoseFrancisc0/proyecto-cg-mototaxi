extends SceneTree
## Flujo de los 3 botones de terrain_demo.tscn:
## 1) T0, 2) erosion sobre el terreno actual (acumulable), 3) restaurar,
## y que guardar/reabrir la escena recupere la configuracion del terreno.

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _small(terrain) -> void:
	terrain.grid_size = 64
	terrain.cell_size = 6.0
	terrain.noise_seed = 4242
	terrain.hydrology_enabled = false
	terrain.preview_roads = false
	terrain.erosion_levels = 0
	terrain.erosion_fluvial = 6
	terrain.erosion_thermal = 3
	terrain.erosion_deposition = 3

func _max_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var m := 0.0
	for i in a.size():
		m = max(m, abs(a[i] - b[i]))
	return m

func _run() -> void:
	var scene := load("res://terrain_demo.tscn") as PackedScene
	var root := scene.instantiate()
	var terrain = root.get_node("Terrain")
	root_add(root)
	await process_frame

	# 1) T0
	_small(terrain)
	terrain.generate_base()
	var n := 65
	var g0: PackedFloat32Array = terrain.ground_bytes.to_float32_array()
	check(g0.size() == n * n, "El suelo T0 debe tener (grid+1)^2 alturas")
	check(terrain.terrain_snapshot.get("params", {}).get("noise_seed") == 4242, "La foto debe guardar la semilla usada")
	check(terrain.terrain_snapshot.get("erosions", [1]).is_empty(), "Un T0 nuevo no tiene erosiones")
	var verts: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var same := true
	for i in verts.size():
		if not is_equal_approx(verts[i].y, g0[i]):
			same = false
			break
	check(same, "Sin rios ni caminos, la malla debe ser exactamente el suelo")

	# 2) Erosion sobre el terreno ACTUAL, aunque el Inspector tenga otra semilla
	terrain.noise_seed = 99999
	terrain.apply_erosion()
	check(terrain.noise_seed == 4242, "Aplicar erosion debe volver a la configuracion del terreno actual")
	var g1: PackedFloat32Array = terrain.ground_bytes.to_float32_array()
	check(_max_diff(g0, g1) > 1e-4, "La erosion debe modificar el suelo")
	check(terrain.terrain_snapshot["erosions"].size() == 1, "Debe registrarse 1 erosion")

	# Debe coincidir con erosionar en C++ el mismo T0 (no con un terreno nuevo)
	var noise := TerrainNoise.new()
	noise.set_seed(4242)
	noise.configure_regions(terrain._region_config())
	var ref := TerrainMesh.new()
	var cfg: Dictionary = terrain._build_cfg()
	ref.generate_mesh(noise, RoadNetwork.new(), 64, 6.0, cfg)
	ref.erode_ground(noise, RoadNetwork.new(), 64, 6.0, cfg)
	check(_max_diff(ref.get_ground_heights(), g1) < 1e-4, "La erosion debe partir del T0 actual")

	# Acumulable
	terrain.apply_erosion()
	var g2: PackedFloat32Array = terrain.ground_bytes.to_float32_array()
	check(_max_diff(g1, g2) > 1e-5, "Una segunda erosion debe seguir modificando el suelo")
	check(terrain.terrain_snapshot["erosions"].size() == 2, "Deben registrarse 2 erosiones")

	# Guardar y reabrir: el Inspector recupera la configuracion del terreno guardado
	terrain.grid_size = 300 # cambio sin regenerar: no debe sobrevivir al reabrir
	var packed := PackedScene.new()
	check(packed.pack(root) == OK, "La escena debe poder empaquetarse")
	var reopened := packed.instantiate()
	var t2 = reopened.get_node("Terrain")
	root_add(reopened)
	await process_frame
	check(t2.grid_size == 64 and t2.noise_seed == 4242, "Al abrir, el Inspector debe mostrar la configuracion del terreno guardado")
	check(_max_diff(t2.ground_bytes.to_float32_array(), g2) < 1e-6, "El suelo debe guardarse con la escena")
	check(t2.terrain_snapshot["erosions"].size() == 2, "El historial de erosiones debe guardarse")
	t2.apply_erosion()
	check(t2.terrain_snapshot["erosions"].size() == 3, "Se debe poder seguir erosionando una escena reabierta")

	# 3) Restaurar: vuelve a la malla, configuracion y suelo guardados
	var saved_mesh = t2._saved_mesh
	t2.noise_seed = 1
	t2.restore_saved_mesh()
	check(t2.mesh == saved_mesh, "Restaurar debe devolver la malla guardada")
	check(t2.noise_seed == 4242 and t2.terrain_snapshot["erosions"].size() == 2, "Restaurar debe devolver la configuracion guardada")
	check(_max_diff(t2.ground_bytes.to_float32_array(), g2) < 1e-6, "Restaurar debe devolver el suelo guardado")

	print("Flujo de botones: %d errores" % failures)
	root.queue_free()
	reopened.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func root_add(node: Node) -> void:
	get_root().add_child(node)
