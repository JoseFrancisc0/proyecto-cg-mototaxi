extends SceneTree
## Prueba sin ventana de guardar y cargar partida, del reloj acelerado de la jornada, del garaje
## (menú y fin del día, con los ahorros de la partida) y de perder la partida:
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

	print("-- Garaje del menú principal (sin abrir la partida)")
	CareerSave.add_savings(100.0)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var loading: LoadingScreen = main.loading
	_check(loading._garage_button.visible, "el menú tiene Garaje")
	loading._open_garage()
	_check(loading._garage.is_visible_in_tree() and not loading._menu.visible, "el garaje se abre aparte de Nueva partida")
	loading._garage.select_vehicle(3)
	loading._garage._on_shop_button()
	var price: float = VehicleCatalog.entry(3)["price"]
	_check(CareerSave.is_owned(3) and CareerSave.get_active() == 3, "se compra y queda en uso")
	_check(is_equal_approx(CareerSave.get_savings(), 100.0 - price), "con los ahorros de la partida (quedan S/ %.2f)" % CareerSave.get_savings())
	loading._close_dialog()
	loading._open_setup()
	_check(loading._vehicle_note.text.contains(VehicleCatalog.entry(3).name), "la configuración dice qué mototaxi se usa")
	loading._on_play()
	_check(loading._notice.visible and loading._notice.text.contains("Continuar") and not loading._starting, "con partida guardada no se empieza otra (una sola carrera)")
	loading._close_dialog()

	print("-- Continuar desde el menú")
	_check(loading._continue_game.visible and loading._continue_game.text == "Continuar · Día 3", "el menú ofrece \"%s\"" % loading._continue_game.text)
	_check(not loading._new_game.visible, "sin \"Nueva partida\" ni \"Jugar\"")
	_check(loading._free_button.visible and loading._free_button.text == "Modo libre", "con Modo libre")
	loading._on_continue()
	while not main.hud.visible:
		await process_frame
	for i in 10: await physics_frame
	session = main.session
	_check(session.day == 3 and is_equal_approx(session.quota, session.quota_for(3)), "sigue en el día 3 con su cuota")
	_check(is_equal_approx(main.race.earnings, 7.5), "con lo ganado (S/ %.2f)" % main.race.earnings)
	_check(session.get_clock_text() == "13:00" or session.get_clock_text() == "13:01", "a la misma hora (%s)" % session.get_clock_text())
	_check(is_equal_approx(main.moto.health, 60.0), "con la misma vida")
	_check(main.moto.vehicle_index == 3, "con la mototaxi elegida en el garaje")
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
	var savings := CareerSave.get_savings()
	_check(is_equal_approx(savings, 100.0 - price + 2.0), "los S/ 2 que sobran van a los ahorros (S/ %.2f)" % savings)

	print("-- Garaje al terminar el día")
	var screen: GameOverScreen = main.game_over_screen
	_check(screen._garage_button.visible, "el resumen del día ofrece Garaje")
	screen.open_garage()
	_check(screen._garage.is_visible_in_tree() and not screen._box.visible, "se abre el garaje")
	screen._garage.select_vehicle(CareerSave.STARTER)
	screen._garage._on_shop_button()
	_check(CareerSave.get_active() == CareerSave.STARTER, "\"Usar esta\" cambia la mototaxi en uso")
	screen.close_garage()
	_check(screen._box.visible and not screen._garage_panel.visible, "Volver regresa al resumen")
	screen.next_day_requested.emit()
	for i in 5: await physics_frame
	_check(session.day == 4 and main.moto.vehicle_index == CareerSave.STARTER, "el día 4 empieza con la nueva elegida")

	print("-- Perder la partida")
	session._end("prueba")
	await process_frame
	_check(not CareerSave.has_game() and CareerSave.get_savings() == 0.0, "se borran la partida guardada y sus ahorros")
	_check(CareerSave.is_owned(3), "las mototaxis compradas se quedan")
	_check(screen._details.text.contains("Se perdieron los ahorros"), "la pantalla final lo dice")
	_check(not screen._garage_button.visible, "sin garaje en el fin de partida")

	main.queue_free()
	await process_frame
	CareerSave.reset()
	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d fallas" % _fails))
	quit(1 if _fails > 0 else 0)
