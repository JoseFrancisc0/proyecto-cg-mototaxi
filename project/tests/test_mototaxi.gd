extends SceneTree
## Prueba sin ventana del manejo de la mototaxi:
##   Godot_console.exe --headless --path project -s res://tests/test_mototaxi.gd

var _fails := 0
var moto: Mototaxi
var _min_up := 1.0

func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1

func _sim(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame
		_min_up = minf(_min_up, moto.global_basis.y.dot(Vector3.UP))

func _yaw() -> float:
	return atan2(moto.global_basis.z.x, moto.global_basis.z.z)

func _initialize() -> void:
	# Suelo plano con la cara superior en y = 0.
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	gs.shape = box
	gs.position.y = -1.0
	ground.add_child(gs)
	root.add_child(ground)

	moto = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	root.add_child(moto)

	print("-- Suelo plano")
	moto.place_at(Vector3.ZERO, 0.0)
	await _sim(2.0)
	var contacts := 0
	for c in moto.get_children():
		if c is VehicleWheel3D and c.is_in_contact():
			contacts += 1
	_check(contacts == 3, "en reposo: %d/3 ruedas en contacto" % contacts)
	_check(moto.linear_velocity.length() < 0.2, "en reposo queda quieta (%.2f m/s)" % moto.linear_velocity.length())
	_check(moto.is_upright(), "en reposo está derecha")

	_min_up = 1.0
	var p0 := moto.global_position
	moto.throttle = 1.0
	await _sim(4.0)
	var v4 := moto.get_speed_kmh()
	_check(moto.get_forward_speed() > 0.0 and (moto.global_position - p0).dot(Vector3(0, 0, 1)) > 10.0, "acelerar avanza hacia +Z")
	_check(v4 > 30.0, "0-4 s: %.0f km/h" % v4)
	await _sim(8.0)
	var vmax := moto.get_speed_kmh()
	_check(vmax > 55.0 and vmax < moto.max_speed_kmh * 1.05, "velocidad máxima %.0f km/h (tope %.0f)" % [vmax, moto.max_speed_kmh])
	_check(_min_up > 0.95, "recta sin cabeceo excesivo (min up %.2f)" % _min_up)

	var pb := moto.global_position
	moto.throttle = -1.0
	var t := 0.0
	while moto.get_forward_speed() > 0.5 and t < 8.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_check(t < 5.0, "frenado desde %.0f km/h: %.1f s, %.0f m" % [vmax, t, moto.global_position.distance_to(pb)])
	await _sim(3.0)
	_check(moto.get_forward_speed() < -1.0, "reversa: %.1f km/h" % (moto.get_forward_speed() * 3.6))

	# Curva a velocidad media hacia la izquierda.
	moto.place_at(Vector3.ZERO, 0.0)
	moto.throttle = 0.0
	await _sim(1.0)
	_min_up = 1.0
	moto.throttle = 0.6
	moto.steer_input = 1.0
	# Se acumula el giro cuadro a cuadro: puede superar media vuelta en 4 s.
	var dyaw := 0.0
	var prev := _yaw()
	for i in int(4.0 * Engine.physics_ticks_per_second):
		await physics_frame
		_min_up = minf(_min_up, moto.global_basis.y.dot(Vector3.UP))
		dyaw += rad_to_deg(wrapf(_yaw() - prev, -PI, PI))
		prev = _yaw()
	_check(dyaw > 45.0, "steer +1 gira a la izquierda (%.0f° en 4 s)" % dyaw)
	_check(_min_up > 0.7, "curva media sin volcar (min up %.2f)" % _min_up)

	# Volantazo a fondo a velocidad máxima: la reducción de giro debe evitar el vuelco.
	moto.place_at(Vector3.ZERO, 0.0)
	moto.steer_input = 0.0
	moto.throttle = 1.0
	await _sim(10.0)
	_min_up = 1.0
	moto.steer_input = -1.0
	await _sim(3.0)
	_check(_min_up > 0.5, "volantazo a %.0f km/h sin volcar (min up %.2f)" % [vmax, _min_up])
	moto.steer_input = 0.0
	moto.throttle = 0.0

	# Enderezado automático.
	moto.place_at(Vector3.ZERO, 0.0)
	moto.global_transform = Transform3D(Basis(Vector3(0, 0, 1), PI), Vector3(0, 2.5, 0))
	var resets := [0]
	moto.was_reset.connect(func(): resets[0] += 1)
	await _sim(4.5)
	_check(resets[0] >= 1 and moto.is_upright(), "volcada se endereza sola (resets: %d)" % resets[0])

	print("-- Terreno real (TerrainWorld)")
	ground.queue_free()
	var world: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	world.grid_size = 256
	world.generate_on_ready = false
	root.add_child(world)
	world.generate(67)
	moto.terrain = world
	await physics_frame
	var lm := world.get_landmarks()
	var start: Vector3 = lm[0]["position"]
	var route := world.find_route(start, lm[1]["position"])
	var d := route[mini(4, route.size() - 1)] - start
	moto.place_at(start, atan2(d.x, d.z))
	await _sim(2.0)
	_check(moto.is_upright() and absf(moto.global_position.y - world.get_height(start.x, start.z)) < 0.5,
		"aparece sobre el camino y se asienta")
	var ps := moto.global_position
	moto.throttle = 0.7
	await _sim(4.0)
	_check(moto.global_position.distance_to(ps) > 15.0, "avanza sobre el terreno: %.0f m en 4 s" % moto.global_position.distance_to(ps))
	# Frena hasta detenerse y suelta: debe quedarse quieta (freno de parada).
	moto.throttle = -1.0
	var tb := 0.0
	while moto.get_forward_speed() > 0.3 and tb < 6.0:
		await physics_frame
		tb += 1.0 / Engine.physics_ticks_per_second
	moto.throttle = 0.0
	await _sim(3.0)
	_check(moto.linear_velocity.length() < 0.3, "frena y se detiene (%.1f s, %.2f m/s)" % [tb, moto.linear_velocity.length()])
	var parked := moto.global_position
	var n := world.get_normal(parked.x, parked.z)
	await _sim(3.0)
	_check(moto.global_position.distance_to(parked) < 0.3,
		"no rueda estando detenida (pendiente %.0f°, se movió %.2f m)" % [rad_to_deg(acos(n.y)), moto.global_position.distance_to(parked)])

	print("RESULTADO: ", "OK" if _fails == 0 else "%d fallos" % _fails)
	quit(_fails)
