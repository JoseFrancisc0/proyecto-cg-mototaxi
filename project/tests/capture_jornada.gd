extends SceneTree
## Capturas con ventana de la jornada: HUD con cuota, retraso, mapa completo y resumen del día.
##   Godot_console.exe --path project -s res://tests/capture_jornada.gd
## Guarda en output/game_review/. Usa un archivo de carrera aparte.

func save_frame(path: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/game_review/" + path + ".png")


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	CareerSave.path = "user://test_capture.cfg"
	CareerSave.reset()
	root.size = Vector2i(1440, 900)
	var main: Node = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	while not main.hud.visible:
		await process_frame
	for i in 60: await physics_frame
	var race: RaceManager = main.race
	var moto: Mototaxi = main.moto
	moto.place_at(race.pickup_zone.global_position, moto.rotation.y)
	for i in 30: await physics_frame
	race.time_left = 0.0
	race.late_time = 8.0
	race.earnings = 6.4
	for i in 20: await physics_frame
	await save_frame("6_jornada_tarde")
	main._unhandled_input(_key(KEY_M))
	await save_frame("7_mapa_completo")
	main._unhandled_input(_key(KEY_M))
	race.earnings = main.session.quota + 4.2
	main.session.day_time_left = 0.0
	main.session.overtime = false
	race.state = RaceManager.State.ENTREGADO
	for i in 10: await physics_frame
	await save_frame("8_dia_completo")
	main.next_day()
	for i in 10: await physics_frame
	main.pause()
	main._on_save_requested()
	await save_frame("9_pausa_guardada")
	main.resume()
	main.queue_free()
	await process_frame
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await save_frame("10_menu_continuar")
	CareerSave.reset()
	print("Capturas de la jornada guardadas")
	quit()


func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	return e
