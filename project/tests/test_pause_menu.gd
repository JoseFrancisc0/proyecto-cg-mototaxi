extends SceneTree
## Menú de pausa: Esc pausa la partida (mototaxi y reloj del pasajero quietos), vuelve a
## continuar, reiniciar deja la partida corriendo y "Menú principal" vuelve a la portada.
##   Godot --headless --fixed-fps 60 --path project -s res://tests/test_pause_menu.gd

var errors := 0


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + what)
	if not ok:
		errors += 1


func _press_pause() -> void:
	var e := InputEventAction.new()
	e.action = PauseMenu.ACTION
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	var r := InputEventAction.new()
	r.action = PauseMenu.ACTION
	r.pressed = false
	Input.parse_input_event(r)
	await process_frame


func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	while is_instance_valid(main.loading) and main.pause_menu == null:
		await process_frame
	for i in 30:
		await physics_frame
	var moto: Mototaxi = main.moto
	var race: RaceManager = main.race
	moto.use_input = false

	print("-- Pausa")
	_check(not paused, "la partida corre")
	await _press_pause()
	_check(paused and main.pause_menu.visible, "Esc pausa y muestra el menú")
	# Con un pasajero a bordo el reloj no debe bajar durante la pausa.
	race.state = RaceManager.State.CON_PASAJERO
	race.time_left = 30.0
	moto.linear_velocity = Vector3(0, 0, 10)
	var pos := moto.global_position
	for i in 60:
		await physics_frame
	_check(is_equal_approx(race.time_left, 30.0), "el reloj del pasajero no corre en pausa (%.2f s)" % race.time_left)
	_check(moto.global_position.distance_to(pos) < 0.01, "la mototaxi queda quieta")
	await _press_pause()
	_check(not paused and not main.pause_menu.visible, "Esc otra vez continúa")
	for i in 30:
		await physics_frame
	_check(race.time_left < 30.0, "al continuar el reloj vuelve a correr (%.2f s)" % race.time_left)

	print("-- Reiniciar")
	await _press_pause()
	main.pause_menu.open_scenario()
	_check(main.pause_menu._scenario.visible and not main.pause_menu._box.visible, "Reiniciar partida abre el escenario")
	_check(main.pause_menu._scenario._note.text.contains("pierdes los ahorros"), "y avisa que se pierden los ahorros")
	main.pause_menu._scenario.confirm()  # Mismo escenario: sin regenerar.
	await process_frame
	_check(not paused and not main.pause_menu.visible, "reiniciar cierra el menú y sigue la partida")
	_check(current_scene == main, "en el mismo escenario no se recarga la escena")
	_check(race.state == RaceManager.State.LIBRE, "turno nuevo (buscando pasajero)")

	print("-- Volumen")
	var slider: HSlider = main.pause_menu._volume
	slider.value = 50.0
	_check(absf(db_to_linear(AudioServer.get_bus_volume_db(0)) - 0.5) < 0.01, "el volumen general baja a 50%")
	slider.value = 100.0

	print("-- Menú principal")
	await _press_pause()
	main.pause_menu.menu_requested.emit()
	for i in 10:
		await process_frame
	var fresh = current_scene
	_check(fresh != null and fresh != main and fresh.scene_file_path == "res://main.tscn", "se recarga la escena principal")
	_check(paused and is_instance_valid(fresh.loading), "aparece la portada (menú de inicio, juego en espera)")
	_check(fresh.pause_menu == null, "sin partida en curso hasta elegir en el menú")

	print("RESULTADO: " + ("OK" if errors == 0 else "%d fallos" % errors))
	quit(errors)
