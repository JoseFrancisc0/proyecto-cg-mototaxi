extends SceneTree
## Prueba sin ventana de la elección de destino: viajes cortos, medios y largos por todo el
## mapa, el recargo de los largos y que no se pidan si no alcanza la jornada:
##   Godot_console.exe --headless --path project -s res://tests/test_destinos.gd

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _initialize() -> void:
	var world: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	world.generate_on_ready = false
	world.use_editor_scene = true
	root.add_child(world)
	world.generate()
	var race := RaceManager.new()
	race.world = world
	root.add_child(race)
	race._rng.seed = 7
	var lms := world.get_landmarks()

	print("-- Reparto de viajes desde todo el mapa")
	var counts := [0, 0, 0]
	var max_d := 0.0
	var spread := {}  # celdas de 500 m donde cae algún destino
	var n := 600
	for i in n:
		race._pickup_id = lms[race._rng.randi_range(0, lms.size() - 1)]["id"]
		var from := race._landmark_pos(race._pickup_id)
		var id := race._pick_destination(from, race._roll_ride_kind())
		if id < 0:
			continue
		var to := race._landmark_pos(id)
		var d := Vector2(to.x - from.x, to.z - from.z).length()
		var span := race.ride_range(race.ride_kind)
		if race.ride_kind != RaceManager.RideKind.CORTO and (d < span.x or d > span.y):
			_check(false, "destino fuera del rango de su tipo (%.0f m)" % d)
		counts[race.ride_kind] += 1
		max_d = maxf(max_d, d)
		spread[Vector2i(floori(to.x / 500.0), floori(to.z / 500.0))] = true
	print("  corto %d · medio %d · largo %d · más lejano %.0f m · %d celdas de 500 m" % [counts[0], counts[1], counts[2], max_d, spread.size()])
	_check(counts[0] > counts[1] and counts[1] > counts[2], "la mayoría son cortos, luego medios, luego largos")
	_check(counts[2] > n * 0.08, "salen viajes largos (%d)" % counts[2])
	_check(max_d > 1200.0, "algún destino cruza el mapa (%.0f m)" % max_d)

	print("-- Rentabilidad por minuto (con ~30 s de ir a recoger)")
	var per_min := func(length: float) -> float:
		return race.compute_fare(length) / ((race.compute_time_limit(length) + 33.0) / 60.0)
	var short_rate: float = per_min.call(250.0)
	var long_rate: float = per_min.call(2200.0)
	print("  corto S/ %.2f/min · medio S/ %.2f/min · largo S/ %.2f/min" % [short_rate, per_min.call(900.0), long_rate])
	_check(long_rate > short_rate, "el viaje largo rinde más por minuto que uno corto")

	print("-- Fin de jornada: sin viajes largos si no alcanza el tiempo")
	race.time_budget = 60.0
	var long_late := 0
	for i in 100:
		race._pickup_id = lms[race._rng.randi_range(0, lms.size() - 1)]["id"]
		race._pick_destination(race._landmark_pos(race._pickup_id), RaceManager.RideKind.LARGO)
		if race.ride_kind != RaceManager.RideKind.CORTO:
			long_late += 1
	_check(long_late == 0, "con 60 s de jornada solo salen viajes cortos")

	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d fallos" % _fails))
	quit(0 if _fails == 0 else 1)
