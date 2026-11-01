extends SceneTree
## Prueba sin ventana de lo agregado para S12-S13 (juego):
##   regiones con mayoría/solo (biome_bias), ruta por vías, vida y daño, vuelcos,
##   fin de partida (atrapado, fuera del mapa, pasajeros perdidos), tiempo con pendiente y pago.
##   Godot_console.exe --headless --path project -s res://tests/test_s13_juego.gd

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Fracción del mapa donde gana cada bioma (costa, sierra, selva).
func _shares(bias: Vector3, seed: int) -> Vector3:
	var t := TerrainNoise.new()
	t.set_seed(seed)
	var cfg := {"enabled": true, "extent": 1536.0, "region_patches": 16}
	if bias != Vector3(-1, -1, -1):
		cfg["biome_bias"] = bias
	t.configure_regions(cfg)
	var count := Vector3.ZERO
	for i in 60:
		for j in 60:
			var w := t.get_biome_weights(-768.0 + i * 25.6, -768.0 + j * 25.6)
			count[w.max_axis_index()] += 1
	return count / 3600.0


func _initialize() -> void:
	print("-- Regiones (biome_bias)")
	for seed in [2, 67, 2026]:
		var none := _shares(Vector3(-1, -1, -1), seed)
		var zero := _shares(Vector3.ZERO, seed)
		_check(none.is_equal_approx(zero), "semilla %d: sin bias = como antes %s" % [seed, none])
		var major := _shares(Vector3(0.1, 0.1, 0.8), seed)
		_check(major.z > 0.55, "semilla %d: mayoría de selva %.0f%%" % [seed, major.z * 100])
		var only := _shares(Vector3(0, 1, 0), seed)
		_check(only.y > 0.999, "semilla %d: solo sierra %.1f%%" % [seed, only.y * 100])
		var coast := _shares(Vector3(0.8, 0.1, 0.1), seed)
		_check(coast.x > 0.55 and coast.y > 0.0 and coast.z > 0.0, "semilla %d: mayoría de costa %.0f%% y quedan las otras" % [seed, coast.x * 100])

	var world: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	world.generate_on_ready = false
	world.use_editor_scene = true
	root.add_child(world)
	world.generate()

	print("-- Ruta por vías")
	var lms := world.get_landmarks()
	var road_pts := {}
	for r in world.get_roads():
		for q in r["path"]:
			road_pts[Vector2i(roundi(q.x), roundi(q.z))] = true
	var tried := 0
	var ok_routes := 0
	var on_road_total := 0.0
	for i in range(0, lms.size(), 7):
		var a: Vector3 = lms[i]["position"]
		var b: Vector3 = lms[(i * 13 + 5) % lms.size()]["position"]
		if not world.is_reachable(a, b) or a.distance_to(b) < 50.0:
			continue
		tried += 1
		var path := world.find_road_route(a, b)
		if path.size() >= 2 and path[0].distance_to(a) < 15.0 and path[-1].distance_to(b) < 15.0:
			ok_routes += 1
		var on := 0
		for p in path:
			if road_pts.has(Vector2i(roundi(p.x), roundi(p.z))):
				on += 1
		on_road_total += float(on) / maxf(path.size(), 1)
	_check(tried > 0 and ok_routes == tried, "%d de %d rutas unen origen y destino" % [ok_routes, tried])
	_check(tried > 0 and on_road_total / tried > 0.8, "en promedio %.0f%% de la ruta va por vías" % [100.0 * on_road_total / maxf(tried, 1)])

	print("-- Tiempo y pago")
	var race := RaceManager.new()
	var flat := PackedVector3Array([Vector3(0, 0, 0), Vector3(250, 0, 0)])
	var hill := PackedVector3Array([Vector3(0, 0, 0), Vector3(250, 50, 0)])
	_check(is_equal_approx(race.compute_route_time(flat), race.compute_time_limit(250.0)), "en llano = solo por largo")
	_check(race.compute_route_time(hill) > race.compute_route_time(flat) * 1.4, "subida 0.2 da más tiempo (%.0f s vs %.0f s)" % [race.compute_route_time(hill), race.compute_route_time(flat)])
	_check(is_equal_approx(race.compute_fare(1000.0), race.fare_base + race.fare_per_km), "tarifa = base + por km")
	race.free()

	print("-- Vida y choques")
	var start: Vector3 = lms[0]["position"]
	var moto: Mototaxi = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	moto.terrain = world
	root.add_child(moto)
	moto.place_at(start, 0.0)
	await _frames(90)
	_check(moto.health == moto.max_health, "aparecer y asentarse no daña")
	# Pared delante y un empujón a ~40 km/h.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 6, 1)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	var fwd := moto.global_basis.z
	wall.global_position = moto.global_position + fwd * 9.0 + Vector3.UP * 1.5
	wall.look_at(wall.global_position + fwd)
	moto.linear_velocity = fwd * 11.0
	await _frames(90)
	var hit := moto.max_health - moto.health
	_check(hit > 5.0, "chocar una pared a 40 km/h daña (%.0f de vida)" % hit)
	wall.queue_free()

	moto.repair()
	moto.place_at(start, 0.0)
	await _frames(30)
	var before := moto.health
	moto.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), moto.global_position + Vector3.UP * 1.2)
	await _frames(int((moto.flip_reset_time + 1.5) * Engine.physics_ticks_per_second))
	_check(moto.is_upright(), "volcada se endereza sola")
	_check(is_equal_approx(before - moto.health, moto.flip_damage), "el vuelco cuesta %d de vida (perdió %.0f)" % [moto.flip_damage, before - moto.health])

	var destroyed := [false]
	moto.destroyed.connect(func(): destroyed[0] = true)
	moto.apply_damage(1000.0, "choque")
	_check(moto.health == 0.0 and destroyed[0], "sin vida emite destroyed")

	print("-- Fin de partida")
	race = RaceManager.new()
	race.world = world
	race.moto = moto
	root.add_child(race)
	var session := GameSession.new()
	session.world = world
	session.moto = moto
	session.race = race
	session.stuck_time = 3.0
	session.stuck_warning = 2.0
	root.add_child(session)
	var ends: Array = []
	var warnings: Array = []
	session.game_over.connect(func(reason, _stats): ends.append(reason))
	session.warning.connect(func(text, _s): warnings.append(text))

	moto.repair()
	moto.place_at(start, 0.0)
	await _frames(2)
	race.start(1)
	session.start()
	moto.freeze = true  # No puede moverse aunque acelere: atrapada.
	moto.throttle = 1.0
	await _frames(int(3.5 * Engine.physics_ticks_per_second))
	_check(warnings.any(func(w): return w.begins_with("¡Atrapado")), "avisa antes de terminar por atrapado")
	_check(ends.size() == 1 and ends[0].contains("atrapada"), "termina por atrapado: %s" % [ends])
	_check(race.pickup_zone.visible == false and race.route_line.mesh == null, "al terminar se quitan zonas y ruta")
	moto.freeze = false
	moto.throttle = 0.0

	ends.clear()
	moto.place_at(start, 0.0)
	race.start(1)
	session.start()
	var half := world.get_world_size() * 0.5
	moto.global_position = Vector3(half + 20.0, 0.0, 0.0)
	await _frames(3)
	_check(ends.size() == 1 and ends[0].contains("límites"), "termina al salir del mapa: %s" % [ends])

	ends.clear()
	moto.place_at(start, 0.0)
	race.start(1)
	session.start()
	race.failures = session.max_failures - 1
	race.state = RaceManager.State.CON_PASAJERO
	race.time_limit = 10.0
	race.time_left = 0.01
	await _frames(3)
	_check(ends.size() == 1 and ends[0].contains("pasajeros"), "termina al perder %d pasajeros: %s" % [session.max_failures, ends])

	print("-- Pago con ánimo")
	moto.place_at(start, 0.0)
	moto.use_input = false
	race.start(3)
	session.playing = false
	var paid: Array = []
	race.paid.connect(func(f, t): paid.append([f, t]))
	moto.place_at(race.pickup_zone.global_position, 0.0)
	await _frames(10)
	_check(race.state == RaceManager.State.CON_PASAJERO, "recoge al pasajero")
	_check(race.route_line.mesh != null, "la ruta al destino se dibuja")
	moto.apply_damage(30.0, "choque")
	await _frames(2)
	_check(race.mood < 0.6, "los golpes bajan el ánimo (%.2f)" % race.mood)
	moto.place_at(race.dropoff_zone.global_position, 0.0)
	await _frames(10)
	_check(paid.size() == 1, "paga al entregar")
	if paid.size() == 1:
		var fare: float = paid[0][0]
		var tip: float = paid[0][1]
		_check(tip < fare * race.max_tip_ratio * 0.6, "propina baja por los golpes: S/ %.2f de S/ %.2f" % [tip, fare * race.max_tip_ratio])
		_check(is_equal_approx(race.earnings, fare + tip), "ganancias = pasaje + propina (S/ %.2f)" % race.earnings)

	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d fallas" % _fails))
	quit(1 if _fails > 0 else 0)
