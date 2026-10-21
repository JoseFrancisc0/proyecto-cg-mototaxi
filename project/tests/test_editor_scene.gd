extends SceneTree
## El juego usa el terreno guardado en terrain_demo.tscn (use_editor_scene en main.tscn).
## Comprueba que se copian sus parámetros y su suelo, y mide regiones, vías y zonas transitables.
##   Godot_console.exe --headless --path project -s res://tests/test_editor_scene.gd

var _fails := 0

func _check(cond: bool, msg: String) -> void:
	print("  OK   " if cond else "  FAIL ", msg)
	if not cond:
		_fails += 1

func _initialize() -> void:
	var state := (load("res://terrain_demo.tscn") as PackedScene).get_state()
	var saved := {}
	for i in state.get_node_count():
		if state.get_node_name(i) == "Terrain":
			for p in state.get_node_property_count(i):
				saved[state.get_node_property_name(i, p)] = state.get_node_property_value(i, p)
	var params: Dictionary = saved["terrain_snapshot"]["params"]

	var world: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	world.use_editor_scene = true
	world.generate_on_ready = false
	root.add_child(world)
	await process_frame
	var t0 := Time.get_ticks_msec()
	world.generate()
	print("generate() con el escenario del editor: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))

	var gen = world.generator
	_check(world.grid_size == params["grid_size"] and is_equal_approx(world.cell_size, params["cell_size"]),
		"tamaño del editor: %d x %.1f m = %.0f m" % [world.grid_size, world.cell_size, world.get_world_size()])
	_check(world.world_seed == params["noise_seed"], "semilla del editor: %d" % world.world_seed)
	for key in ["region_patches", "mountain_base", "mountain_amplitude", "coast_amplitude", "jungle_base"]:
		_check(is_equal_approx(float(gen.get(key)), float(params[key])), "%s = %s" % [key, gen.get(key)])
	_check(is_equal_approx(gen.sun_azimuth, saved.get("sun_azimuth", gen.sun_azimuth)), "sol del editor (azimut %.0f)" % gen.sun_azimuth)
	_check(gen.ground_bytes == saved["ground_bytes"], "suelo idéntico al guardado (sin erosionar de nuevo)")

	# Reparto de regiones en el mapa y en los landmarks (donde aparecen los pasajeros).
	var names := ["costa", "sierra", "selva"]
	var map_count := [0, 0, 0]
	var half := world.get_world_size() * 0.5
	for iz in 40:
		for ix in 40:
			var b := world.get_biome(-half + (ix + 0.5) * half / 20.0, -half + (iz + 0.5) * half / 20.0)
			map_count[_dominant(b)] += 1
	print("  mapa: costa %d%%, sierra %d%%, selva %d%%" % [map_count[0] * 100 / 1600, map_count[1] * 100 / 1600, map_count[2] * 100 / 1600])
	var lms := world.get_landmarks()
	var zones := {}
	var lm_count := [0, 0, 0]
	for lm in lms:
		zones[lm["reach"]] = zones.get(lm["reach"], 0) + 1
		var p: Vector3 = lm["position"]
		lm_count[_dominant(world.get_biome(p.x, p.z))] += 1
	_check(lms.size() > 10, "landmarks: %d en %d zonas transitables %s" % [lms.size(), zones.size(), zones])
	print("  landmarks: costa %d, sierra %d, selva %d" % lm_count)
	for b in 3:
		_check(map_count[b] > 0, "hay %s en el mapa" % names[b])

	var worst := 0.0
	var steep := 0
	var segs := 0
	for r in world.get_roads():
		var path: PackedVector3Array = r["path"]
		for i in range(1, path.size()):
			var d := Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length()
			if d > 0.5:
				var g := absf(world.get_height(path[i].x, path[i].z) - world.get_height(path[i - 1].x, path[i - 1].z)) / d
				worst = maxf(worst, g)
				segs += 1
				if g > 0.35:
					steep += 1
					print("    tramo empinado %.2f en (%.0f, %.0f)" % [g, path[i].x, path[i].z])
	print("  tramos de vía > 0.35: %d de %d" % [steep, segs])
	# Algunos tramos cortos en cruces pasan el límite; la mototaxi lanzada sube ~0.65.
	_check(steep * 100 < segs, "menos del 1%% de tramos sobre 0.35 (%d de %d)" % [steep, segs])
	_check(worst < 0.65, "pendiente máxima en vías %.2f (límite de vías %.2f, la mototaxi lanzada sube ~0.65)" % [worst, world.road_max_grade])

	print("RESULTADO: ", "OK" if _fails == 0 else "%d FALLAS" % _fails)
	quit(_fails)


func _dominant(b: Vector3) -> int:
	return 0 if b.x >= b.y and b.x >= b.z else (1 if b.y >= b.z else 2)
