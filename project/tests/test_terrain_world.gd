extends SceneTree
## Prueba sin ventana del contrato TerrainWorld:
##   Godot_console.exe --headless --path project -s res://tests/test_terrain_world.gd

var _fails := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		print("  FAIL ", msg)
		_fails += 1

func _initialize() -> void:
	var world: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	world.grid_size = 256
	world.generate_on_ready = false
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	world.generate(67)
	print("generate(67) a 256: %d ms" % (Time.get_ticks_msec() - t0))

	_check(world.get_world_size() == 256.0, "tamaño del mundo 256 m")
	var lm := world.get_landmarks()
	_check(lm.size() > 1, "landmarks: %d" % lm.size())

	var h := world.get_height(0, 0)
	_check(is_finite(h), "get_height(0,0) = %.2f" % h)
	_check(absf(world.get_height(-1000, 0) - world.get_height(-128, 0)) < 0.001, "get_height se recorta en el borde")
	var nrm := world.get_normal(10, 10)
	_check(absf(nrm.length() - 1.0) < 0.001 and nrm.y > 0.0, "get_normal unitaria y hacia arriba")
	var bio := world.get_biome(0, 0)
	_check(absf(bio.x + bio.y + bio.z - 1.0) < 0.001, "get_biome suma 1: %s" % bio)

	if lm.size() > 1:
		var a: Vector3 = lm[0]["position"]
		var b: Vector3 = lm[1]["position"]
		var route := world.find_route(a, b)
		_check(route.size() > 1, "find_route: %d puntos, %.1f m" % [route.size(), TerrainWorld.route_length(route)])
		if route.size() > 1:
			_check(route[0].distance_to(Vector3(a.x, route[0].y, a.z)) < 2.5, "la ruta parte del origen")

	# La colisión debe coincidir con get_height: se espera dos frames de física.
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var max_err := 0.0
	var misses := 0
	for p in [Vector2(0, 0), Vector2(37.3, -51.8), Vector2(-90.5, 12.2), Vector2(100.1, 100.7), Vector2(-120, -120)]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 500, p.y), Vector3(p.x, -500, p.y))
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			misses += 1
		else:
			max_err = maxf(max_err, absf(hit.position.y - world.get_height(p.x, p.y)))
	_check(misses == 0, "el rayo choca con la colisión del terreno")
	_check(max_err < 0.5, "colisión vs get_height, error máx %.3f m" % max_err)

	world.grid_size = 128
	world.cell_size = 2.0
	world.generate(5)
	await physics_frame
	await physics_frame
	var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(21.7, 500, -33.1), Vector3(21.7, -500, -33.1)))
	_check(not hit2.is_empty() and absf(hit2.position.y - world.get_height(21.7, -33.1)) < 0.5, "colisión correcta con cell_size = 2")

	print("RESULTADO: ", "OK" if _fails == 0 else "%d fallos" % _fails)
	quit(_fails)
