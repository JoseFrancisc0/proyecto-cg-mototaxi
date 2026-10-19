extends SceneTree
## Prueba sin ventana del ciclo de carrera (RaceManager + GlowZone + RaceHUD):
##   Godot_console.exe --headless --path project -s res://tests/test_race.gd

var _fails := 0
var moto: Mototaxi
var race: RaceManager

func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _sim(seconds: float) -> void:
	await _frames(int(seconds * Engine.physics_ticks_per_second))

## Deja la mototaxi quieta dentro de la zona.
func _drive_into(zone: GlowZone) -> void:
	moto.place_at(zone.global_position, 0.0)
	await _frames(10)

func _initialize() -> void:
	var world: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	world.grid_size = 256
	world.generate_on_ready = false
	root.add_child(world)
	world.generate(67)

	moto = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	moto.terrain = world
	root.add_child(moto)
	moto.place_at(world.get_landmarks()[0]["position"], 0.0)

	race = RaceManager.new()
	race.world = world
	race.moto = moto
	race.result_time = 1.0
	root.add_child(race)

	var hud := RaceHUD.new()
	root.add_child(hud)
	hud.bind(race, moto)

	var finished: Array = []
	race.ride_finished.connect(func(ok, _t): finished.append(ok))

	await _frames(1)  # Que todo entre al árbol antes de arrancar.
	race.start(1)
	await _frames(2)
	print("-- Libre")
	_check(race.state == RaceManager.State.LIBRE, "arranca en Libre")
	_check(race.pickup_zone.visible and not race.dropoff_zone.visible, "solo se ve la zona de recogida")
	var d := race.get_target_distance()
	_check(d >= race.pickup_min_dist, "pasajero a %.0f m de la mototaxi" % d)

	# Pasar rápido por la zona no sube al pasajero.
	moto.place_at(race.pickup_zone.global_position, 0.0)
	moto.linear_velocity = moto.global_basis.z * 15.0  # 54 km/h
	await _frames(2)
	_check(race.state == RaceManager.State.LIBRE, "pasar a %.0f km/h no recoge" % moto.get_speed_kmh())

	print("-- Recoger y entregar")
	await _drive_into(race.pickup_zone)
	_check(race.state == RaceManager.State.CON_PASAJERO, "entrar despacio recoge al pasajero")
	_check(race.dropoff_zone.visible and not race.pickup_zone.visible, "ahora solo se ve el destino")
	_check(race.route_length > 0.0 and race.time_limit > race.base_time,
		"ruta %.0f m, límite %.0f s" % [race.route_length, race.time_limit])
	var t0 := race.time_left
	await _sim(1.0)
	_check(race.time_left < t0 and race.time_left > t0 - 1.5, "el temporizador corre (%.1f -> %.1f)" % [t0, race.time_left])

	await _drive_into(race.dropoff_zone)
	_check(race.state == RaceManager.State.ENTREGADO and race.deliveries == 1, "llegar a tiempo = Entregado")
	_check(finished == [true], "se emite ride_finished(true)")
	_check(not race.dropoff_zone.visible, "la zona de destino se apaga")

	await _sim(1.2)
	_check(race.state == RaceManager.State.LIBRE and race.pickup_zone.visible, "tras el anuncio aparece otro pasajero")

	print("-- Fallar por tiempo")
	await _drive_into(race.pickup_zone)
	_check(race.state == RaceManager.State.CON_PASAJERO, "recoge al segundo pasajero")
	race.time_left = 0.5
	await _sim(1.0)
	_check(race.state == RaceManager.State.FALLADO and race.failures == 1, "sin tiempo = Fallado")
	_check(finished == [true, false], "se emite ride_finished(false)")
	await _drive_into(race.dropoff_zone)
	_check(race.deliveries == 1, "llegar tarde al destino no cuenta")

	await _sim(1.2)
	_check(race.state == RaceManager.State.LIBRE, "vuelve a Libre")

	print("-- Tiempo límite")
	_check(is_equal_approx(race.compute_time_limit(250.0), race.base_time + 30.0),
		"250 m a 30 km/h = base + 30 s")

	print("RESULTADO: ", "OK" if _fails == 0 else "%d fallos" % _fails)
	quit(_fails)
