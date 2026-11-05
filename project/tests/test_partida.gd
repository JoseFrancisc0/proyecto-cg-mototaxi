extends SceneTree
## Prueba sin ventana de guardar y cargar partida, y del reloj acelerado de la jornada:
##   Godot_console.exe --headless --path project -s res://tests/test_partida.gd
## Usa un archivo de carrera aparte (no toca la partida del jugador).

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	CareerSave.path = "user://test_partida.cfg"
	CareerSave.reset()

	print("-- Partida nueva y reloj")
	var main: Node = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	while not main.hud.visible:
		await process_frame
	for i in 30: await physics_frame
	var session: GameSession = main.session
	_check(session.get_clock_text() == "07:00", "la jornada empieza a las 07:00 (%s)" % session.get_clock_text())
	session.day_time_left = session.day_length * 0.5
	_check(session.get_clock_text() == "13:00", "a mitad del tiempo real son las 13:00 (%s)" % session.get_clock_text())
	_check(session.get_closing_text() == "19:00", "cierra a las 19:00")

	print("-- Guardar")
	session.day = 3
	session.quota = session.quota_for(3)
	main.race.earnings = 7.5
	main.moto.health = 60.0
	var pos: Vector3 = main.moto.global_position
	main.pause()
	main._on_save_requested()
	_check(CareerSave.has_game(), "hay partida guardada")
	_check(main.pause_menu._save_status.text.begins_with("Partida guardada: día 3, 13:00"), "el menú lo confirma (%s)" % main.pause_menu._save_status.text)
	var saved := CareerSave.load_game()
	_check(saved.get("day") == 3 and is_equal_approx(saved.get("earnings", 0.0), 7.5), "guarda día y lo ganado")
	main.resume()
	main.queue_free()
	await process_frame
	await process_frame

	print("-- Continuar desde el menú")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var loading: LoadingScreen = main.loading
	_check(loading._continue_game.visible and loading._continue_game.text == "Continuar · Día 3", "el menú ofrece \"%s\"" % loading._continue_game.text)
	_check(loading._new_game.text == "Nueva partida", "y \"Nueva partida\"")
	loading._on_continue()
	while not main.hud.visible:
		await process_frame
	for i in 10: await physics_frame
	session = main.session
	_check(session.day == 3 and is_equal_approx(session.quota, session.quota_for(3)), "sigue en el día 3 con su cuota")
	_check(is_equal_approx(main.race.earnings, 7.5), "con lo ganado (S/ %.2f)" % main.race.earnings)
	_check(session.get_clock_text() == "13:00" or session.get_clock_text() == "13:01", "a la misma hora (%s)" % session.get_clock_text())
	_check(is_equal_approx(main.moto.health, 60.0), "con la misma vida")
	var d: Vector3 = main.moto.global_position - pos
	_check(Vector2(d.x, d.z).length() < 3.0, "en el mismo lugar (a %.1f m)" % Vector2(d.x, d.z).length())
	_check(main.race.state == RaceManager.State.LIBRE, "con un pasajero nuevo por recoger")

	print("-- Autoguardado al completar el día")
	main.race.earnings = session.quota + 2.0
	session.day_time_left = 0.0
	for i in 5: await physics_frame
	_check(main.game_over_screen.visible and main.game_over_screen._reason.text.begins_with("Partida guardada"), "la pantalla del día dice que se guardó")
	saved = CareerSave.load_game()
	_check(saved.get("day") == 4 and is_equal_approx(saved.get("earnings", -1.0), 0.0), "queda guardado el inicio del día 4")

	main.queue_free()
	await process_frame
	CareerSave.reset()
	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d fallas" % _fails))
	quit(1 if _fails > 0 else 0)
