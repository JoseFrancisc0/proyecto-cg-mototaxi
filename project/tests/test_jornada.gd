extends SceneTree
## Prueba sin ventana de la jornada con cuota, los ahorros del garaje y el mapa completo:
##   Godot_console.exe --headless --path project -s res://tests/test_jornada.gd
## Usa un archivo de carrera aparte (no toca los ahorros del jugador).

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	CareerSave.path = "user://test_carrera.cfg"
	CareerSave.reset()

	print("-- Ahorros y garaje")
	_check(CareerSave.get_savings() == 0.0, "sin progreso: S/ 0")
	_check(CareerSave.is_owned(CareerSave.STARTER) and CareerSave.get_owned().size() == 1, "solo la mototaxi inicial")
	_check(not CareerSave.buy(0), "sin ahorros no se compra")
	CareerSave.add_savings(100.0)
	var price: float = VehicleCatalog.entry(0)["price"]
	_check(CareerSave.buy(0) and CareerSave.is_owned(0), "con ahorros se compra")
	_check(is_equal_approx(CareerSave.get_savings(), 100.0 - price), "se descuenta el precio (quedan S/ %.2f)" % CareerSave.get_savings())
	CareerSave.reset()

	var world: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	world.generate_on_ready = false
	world.use_editor_scene = true
	root.add_child(world)
	world.generate()
	var start: Vector3 = world.get_landmarks()[0]["position"]
	var moto: Mototaxi = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	moto.terrain = world
	root.add_child(moto)
	moto.place_at(start, 0.0)
	var race := RaceManager.new()
	race.world = world
	race.moto = moto
	root.add_child(race)
	var session := GameSession.new()
	session.world = world
	session.moto = moto
	session.race = race
	root.add_child(session)
	var done: Array = []
	var ends: Array = []
	session.day_completed.connect(func(st): done.append(st))
	session.game_over.connect(func(r, st): ends.append([r, st]))
	await _frames(30)

	print("-- Jornada cumplida")
	session.day_length = 1.0
	race.start(1)
	session.start()
	_check(session.day == 1 and is_equal_approx(session.quota, session.quota_base), "día 1, cuota S/ %.2f" % session.quota)
	race.earnings = session.quota + 3.5
	await _frames(int(1.5 * Engine.physics_ticks_per_second))
	_check(done.size() == 1 and ends.is_empty(), "al acabar el reloj con la cuota: día completo")
	if done.size() == 1:
		_check(is_equal_approx(done[0]["saved"], 3.5), "sobran S/ %.2f" % done[0]["saved"])
	_check(is_equal_approx(CareerSave.get_savings(), 3.5), "van a los ahorros")
	_check(CareerSave.get_best_day() == 1, "mejor jornada: día 1")

	print("-- Siguiente día")
	moto.use_input = false
	race.start(2)
	session.next_day()
	_check(session.day == 2 and session.quota > session.quota_base, "día 2, cuota más alta (S/ %.2f)" % session.quota)
	_check(race.earnings == 0.0, "se empieza el día en S/ 0")

	print("-- Con pasajero a bordo se termina el viaje")
	moto.place_at(race.pickup_zone.global_position, 0.0)
	await _frames(10)
	_check(race.state == RaceManager.State.CON_PASAJERO, "recoge al pasajero")
	await _frames(int(1.5 * Engine.physics_ticks_per_second))
	_check(session.overtime and session.playing and ends.is_empty(), "el reloj llegó a 0 pero sigue el viaje")
	race.earnings = 0.0
	moto.place_at(race.dropoff_zone.global_position, 0.0)
	await _frames(10)
	_check(ends.size() == 1 and str(ends[0][0]).contains("cuota"), "sin juntar la cuota: fin de partida (%s)" % [ends])
	_check(is_equal_approx(CareerSave.get_savings(), 3.5), "perder no quita ahorros")

	print("-- Mapa completo")
	var hud := RaceHUD.new()
	root.add_child(hud)
	hud.bind(race, moto)
	var fm := FullMap.new()
	fm.minimap = hud.minimap
	fm.race = race
	fm.moto = moto
	root.add_child(fm)
	await process_frame
	fm.open()
	await process_frame
	_check(fm.visible and hud.minimap.get_background() != null, "se abre con el fondo del minimapa")
	_check(not hud.minimap.get_road_pieces().is_empty(), "tiene las vías")
	fm.close()
	_check(not fm.visible, "se cierra")

	CareerSave.reset()
	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d fallas" % _fails))
	quit(1 if _fails > 0 else 0)
