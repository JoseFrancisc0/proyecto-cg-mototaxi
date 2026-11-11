extends SceneTree
## Una sola carrera + Modo libre (Pendiente 7): cambiar de escenario al terminar el día (el día
## siguiente empieza en el mapa nuevo con los ahorros), reiniciar desde la pausa en otro
## escenario (día 1, sin ahorros) y el Modo libre (sin reloj, pasajeros ni dinero; no toca la
## carrera; reaparece en vez de perder).
##   Godot_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_escenario.gd
## Usa un archivo de carrera aparte (no toca la partida del jugador).

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


## Espera a que la escena principal (recargada o no) tenga la partida en marcha.
func _wait_game() -> Node:
	for i in 20:
		await process_frame
	var main: Node = current_scene
	while main == null or main.session == null or not main.hud.visible:
		await process_frame
		main = current_scene
	for i in 10:
		await physics_frame
	return main


func _run() -> void:
	CareerSave.path = "user://test_escenario.cfg"
	CareerSave.reset()

	print("-- ScenarioPicker")
	var a := {"mode": "editor", "region": 2}
	_check(ScenarioPicker.same(a, {"mode": "editor", "region": 2, "seed": 9}), "terreno guardado: la semilla no importa")
	_check(not ScenarioPicker.same(a, {"mode": "editor", "region": 1}), "otra región es otro escenario")
	_check(not ScenarioPicker.same({"mode": "seed", "seed": 1}, {"mode": "seed", "seed": 2}), "otra semilla es otro escenario")
	_check(ScenarioPicker.describe({"mode": "seed", "seed": 42, "region": 1, "region_only": true}) == "Semilla 42 · Costa (solo) · Normal", "resumen del escenario")

	print("-- Cambiar de escenario al terminar el día")
	CareerSave.launch = {"mode": "editor", "region": 0}
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main = await _wait_game()
	_check(main.region == 0 and main.session.day == 1, "carrera nueva en la región mixta, día 1")
	_check(CareerSave.launch.is_empty(), "el arranque directo se usa una sola vez")
	main.race.earnings = main.session.quota + 5.0
	main.session.day_time_left = 0.0
	for i in 5: await physics_frame
	var screen: GameOverScreen = main.game_over_screen
	_check(screen.visible and screen.is_day_complete() and screen._scenario_button.visible, "el resumen del día ofrece Cambiar escenario")
	screen.open_scenario()
	_check(screen._scenario.visible and not screen._box.visible, "se abre el panel del escenario")
	_check(screen._scenario._confirm.text == "Ir al día 2", "para el día siguiente (%s)" % screen._scenario._confirm.text)
	screen._scenario.picker.region.select(2)  # Sierra
	screen._scenario.confirm()
	main = await _wait_game()
	_check(main.region == 2, "el mapa se genera en la sierra")
	_check(main.session.day == 2, "y sigue en el día 2 (día %d)" % main.session.day)
	_check(is_equal_approx(CareerSave.get_savings(), 5.0), "con los ahorros (S/ %.2f)" % CareerSave.get_savings())
	_check(int(CareerSave.load_game()["choice"]["region"]) == 2, "la partida guardada recuerda el escenario nuevo")

	print("-- Garaje en la pausa de la carrera")
	main.pause()
	var before: int = main.moto.vehicle_index
	var swap: int = (before + 1) % VehicleCatalog.VEHICLES.size()
	CareerSave.add_savings(100000.0)
	CareerSave.buy(swap)
	CareerSave.set_active(before)
	main.moto.apply_damage(30.0, "test")
	var hp: float = main.moto.health
	main.pause_menu.open()
	_check(main.pause_menu._garage_button.visible, "la pausa de la carrera tiene Garaje")
	main.pause_menu.open_garage()
	main.pause_menu.garage.select_vehicle(swap)
	main.pause_menu.garage._on_use()
	main.pause_menu._close_scenario()  # "Volver"
	_check(main.moto.vehicle_index == swap, "al volver maneja la otra mototaxi")
	_check(is_equal_approx(main.moto.health, hp), "con la misma vida (%.0f): cambiar no repara" % main.moto.health)
	_check(main.session.day == 2, "y sigue el mismo día")
	CareerSave.set_active(before)
	main.pause_menu.open_garage()
	main.pause_menu._close_scenario()

	print("-- Reiniciar desde la pausa en otro escenario")
	main.pause_menu.open_scenario()
	_check(main.pause_menu._scenario.visible, "la pausa muestra el escenario al reiniciar")
	main.pause_menu._scenario.picker.region.select(1)  # Costa
	main.pause_menu._scenario.confirm()
	main = await _wait_game()
	_check(main.region == 1 and main.session.day == 1, "empieza de cero en la costa, día 1")
	_check(CareerSave.get_savings() == 0.0, "sin ahorros")

	print("-- Perder y empezar en otro escenario")
	main.session._end("prueba")
	await process_frame
	screen = main.game_over_screen
	_check(screen._scenario_button.visible and not screen._garage_button.visible, "el fin de partida ofrece Cambiar escenario")
	screen.open_scenario()
	_check(screen._scenario._confirm.text == "Empezar de cero", "para el día 1")
	screen._scenario.picker.region.select(3)  # Selva
	screen._scenario.confirm()
	main = await _wait_game()
	_check(main.region == 3 and main.session.day == 1, "día 1 en la selva")

	print("-- Modo libre")
	main.save_game()
	var career := CareerSave.load_game()
	main.pause()
	main.pause_menu.menu_requested.emit()
	for i in 10: await process_frame
	var loading: LoadingScreen = current_scene.loading
	loading._open_free_setup()
	_check(loading._dialog_title.text == "Modo libre" and loading._play.text == "Explorar", "el menú abre la configuración del Modo libre")
	loading._region.select(2)
	loading._on_play()
	main = await _wait_game()
	_check(main.free_mode and main.session.free_mode, "entra al Modo libre")
	_check(main.race.state == RaceManager.State.FALLADO and not main.race.passenger.visible, "sin pasajeros")
	_check(main.moto.vehicle_index == CareerSave.get_active(), "con la mototaxi en uso (comprada)")
	_check(main.hud._score.text.begins_with("MODO LIBRE"), "el HUD dice Modo libre, sin cuota")
	var left: float = main.session.day_time_left
	for i in 60: await physics_frame
	_check(is_equal_approx(main.session.day_time_left, left), "el reloj no corre")
	var over := []
	main.session.game_over.connect(func(r, _s): over.append(r))
	main.moto.global_position += Vector3(500, 0, 0)
	main.session._end("Saliste de los límites del mapa")
	for i in 3: await process_frame
	_check(over.is_empty() and main.session.playing and not main.game_over_screen.visible, "salirse no termina nada: se reaparece")
	_check(main.save_game().is_empty() and CareerSave.load_game() == career, "no guarda ni toca la carrera")
	main.pause()
	_check(not main.pause_menu._save.visible and main.pause_menu._respawn.visible, "la pausa ofrece Volver al inicio (sin Guardar)")
	_check(main.pause_menu._restart.text == "Cambiar escenario", "y Cambiar escenario")
	# Pendiente 12: garaje dentro del Modo libre.
	var first: int = main.moto.vehicle_index
	var other: int = (first + 1) % VehicleCatalog.VEHICLES.size()
	CareerSave.add_savings(100000.0)
	CareerSave.buy(other)
	CareerSave.set_active(first)
	_check(main.pause_menu._garage_button.visible, "la pausa del Modo libre tiene Garaje")
	main.pause_menu.open_garage()
	main.pause_menu.garage.select_vehicle(other)
	main.pause_menu.garage._on_use()
	main.pause_menu._close_scenario()  # "Volver"
	_check(main.moto.vehicle_index == other and CareerSave.get_active() == other, "al volver del garaje ya maneja la otra mototaxi")
	main.resume()
	_check(not get_root().get_tree().paused and main.moto.vehicle_index == other, "y sigue explorando con ella")
	main.pause()
	main.pause_menu.open_scenario()
	main.pause_menu._scenario.picker.region.select(1)
	main.pause_menu._scenario.confirm()
	main = await _wait_game()
	_check(main.free_mode and main.region == 1, "cambia de escenario y sigue en Modo libre")

	main.queue_free()
	await process_frame
	CareerSave.reset()
	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d fallas" % _fails))
	quit(1 if _fails > 0 else 0)
