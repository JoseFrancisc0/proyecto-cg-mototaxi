extends SceneTree
## Capturas del tráfico (RoadTraffic) en el juego real: cada tipo de vehículo visto de 3/4 por
## delante (para ver que mira hacia donde avanza) y una vista con la cámara del juego.
##   Godot --path project -s res://tests/capture_trafico.gd -- [--editor | --seed=N]  (con ventana)
## Guarda output/trafico/<tipo>.png y output/trafico/juego_<tipo>.png


func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	await process_frame
	await process_frame
	while is_instance_valid(main.loading):
		await process_frame
	var world: TerrainWorld = main.world
	var traffic: RoadTraffic = main.traffic
	main.moto.use_input = false
	main.race.stop()
	main.hud.visible = false
	main.session.process_mode = Node.PROCESS_MODE_DISABLED
	main.animals.density = 0.0
	main.animals.clear_all()
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/trafico").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)

	# Tramos rectos y parejos de carretera o avenida.
	var good: Array[Dictionary] = []
	for s in traffic._sites:
		if s["kind"] == 0:
			continue
		var p: Vector3 = s["p"]
		var a: Vector3 = p + s["dir"] * 25.0
		var b: Vector3 = p - s["dir"] * 25.0
		if absf(world.get_height(a.x, a.z) - p.y) > 2.0 or absf(world.get_height(b.x, b.z) - p.y) > 2.0:
			continue
		if world.get_offroad_amount(a.x, a.z) > 0.3 or world.get_offroad_amount(b.x, b.z) > 0.3:
			continue
		good.append(s)
	print("tramos buenos: %d de %d" % [good.size(), traffic._sites.size()])
	if good.is_empty():
		quit(1)
		return

	var cam := Camera3D.new()
	cam.far = 3000.0
	root.add_child(cam)
	var n := 0
	for kind in RoadTraffic.TYPES:
		var site: Dictionary = good[(n * 11) % good.size()]
		n += 1
		var fwd: Vector3 = site["dir"]
		traffic.clear_all()
		traffic._spawn_timer = 1e9
		main.moto.place_at(site["p"] - fwd * 40.0 + Vector3(-fwd.z, 0, fwd.x) * 30.0, atan2(fwd.x, fwd.z))
		await process_frame
		var v := traffic.spawn(site, kind, 1)
		for i in 20:
			await process_frame
		# De 3/4 por delante, a la altura de los ojos.
		cam.current = true
		var c: Vector3 = v["pos"]
		var f: Vector3 = v["fwd"]
		var right := Vector3(-f.z, 0, f.x)
		var eye: Vector3 = c + f * 9.0 - right * 4.0
		eye.y = world.get_height(eye.x, eye.z) + 1.7
		cam.global_position = eye
		cam.look_at(c + Vector3.UP * 1.0, Vector3.UP)
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png(dir.path_join(kind + ".png"))
		# Como en el juego: la mototaxi detrás del vehículo.
		cam.current = false
		main.cam.current = true
		var behind: Vector3 = c - f * 14.0 - right * 1.0
		main.moto.place_at(behind, atan2(f.x, f.z))
		main.cam.snap()
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png(dir.path_join("juego_" + kind + ".png"))
		print("%s: medio ancho %.2f, medio largo %.2f, FPS %d" % [kind, v["half_w"], v["half_l"], Engine.get_frames_per_second()])
	quit(0)
