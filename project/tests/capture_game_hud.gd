extends SceneTree
## Capturas reales del juego (con ventana): HUD, ruta dibujada, ánimo, aviso y pantalla final.
##   Godot_console.exe --path project -s res://tests/capture_game_hud.gd
## Guarda en output/game_review/.

func save_frame(path: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/game_review/" + path + ".png")


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1440, 900)
	var main: Node = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	while not main.hud.visible:
		await process_frame
	for i in 90: await physics_frame
	await save_frame("1_libre_ruta_al_pasajero")
	var race: RaceManager = main.race
	var moto: Mototaxi = main.moto
	moto.place_at(race.pickup_zone.global_position, moto.rotation.y)
	for i in 20: await physics_frame
	# Mirar a lo largo de la ruta al destino.
	var ahead := race.route_line.point_ahead(12.0)
	if ahead != Vector3.INF:
		var d := ahead - moto.global_position
		moto.place_at(moto.global_position - Vector3.UP * moto.spawn_height, atan2(d.x, d.z))
		main.cam.snap()
	moto.apply_damage(25.0, "choque")
	for i in 60: await physics_frame
	await save_frame("2_con_pasajero_ruta_y_animo")
	main.session.warning.emit("¡Atrapado! Sal de aquí", 4.2)
	await save_frame("3_aviso_atrapado")
	main.session._end("La mototaxi quedó destrozada")
	await save_frame("4_fin_de_partida")
	main.game_over_screen.retry_requested.emit()
	for i in 30: await physics_frame
	print("Reintentar: vida %.0f, estado %s, jugando %s, pausa %s, HUD %s" % [
		moto.health, RaceManager.state_name(race.state), main.session.playing, paused, main.hud.visible])
	await save_frame("5_reintentar")
	print("Capturas guardadas en output/game_review/")
	quit()
