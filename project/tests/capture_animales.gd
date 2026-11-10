extends SceneTree
## Capturas de los animales (RoadAnimals) en el juego real: un grupo de cada especie y una vista
## con la cámara del juego, con la mototaxi acercándose a un grupo.
##   Godot --path project -s res://tests/capture_animales.gd -- [--editor | --seed=N --region=sierra]  (con ventana)
## Guarda output/animales/<especie>.png y output/animales/juego_<especie>.png


func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	await process_frame
	await process_frame
	while is_instance_valid(main.loading):
		await process_frame
	var world: TerrainWorld = main.world
	var animals: RoadAnimals = main.animals
	main.moto.use_input = false
	main.race.stop()
	main.hud.visible = false
	main.session.process_mode = Node.PROCESS_MODE_DISABLED  # Sin fin de partida.
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/animales").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)

	# Tramos con suelo parejo a un costado y la vía siguiendo 20 m atrás (buenos para la foto).
	var good: Array[Dictionary] = []
	for s in animals._sites:
		if not animals._side_ok(s, 1.0) and not animals._side_ok(s, -1.0):
			continue
		var p: Vector3 = s["p"]
		var mid: Vector3 = p - s["dir"] * 20.0
		if world.get_offroad_amount(mid.x, mid.z) > 0.3 or absf(world.get_height(mid.x, mid.z) - p.y) > 2.0:
			continue
		good.append(s)
	print("tramos buenos: %d de %d" % [good.size(), animals._sites.size()])
	if good.is_empty():
		quit(1)
		return

	var cam := Camera3D.new()
	cam.far = 3000.0
	root.add_child(cam)
	var n := 0
	for species in RoadAnimals.SPECIES:
		var site: Dictionary = good[(n * 7) % good.size()]
		n += 1
		var fwd: Vector3 = site["dir"]
		var side := Vector3(fwd.z, 0, -fwd.x)
		animals.clear_all()
		animals.density = 0.0  # Solo el grupo de la foto.
		main.moto.place_at(site["p"] - fwd * 45.0, atan2(fwd.x, fwd.z))
		await process_frame
		animals._spawn_group(site, species)
		var g: Dictionary = animals.groups[0]
		g["mode"] = RoadAnimals.Mode.ASIDE  # Que no crucen por la mototaxi.
		# De costado, a la altura de los ojos.
		cam.current = true
		var c := animals._group_center(g)
		var eye: Vector3 = site["p"] - fwd * 7.0
		eye.y = world.get_height(eye.x, eye.z) + 1.6
		cam.global_position = eye
		cam.look_at(c + Vector3.UP * 0.4, Vector3.UP)
		for i in 30:
			await process_frame
		root.get_texture().get_image().save_png(dir.path_join(species + ".png"))
		# Como en el juego: la cámara de persecución detrás de la mototaxi.
		cam.current = false
		main.cam.current = true
		main.moto.place_at(site["p"] - fwd * 20.0, atan2(fwd.x, fwd.z))
		main.cam.snap()
		for i in 30:
			await process_frame
		root.get_texture().get_image().save_png(dir.path_join("juego_" + species + ".png"))
		print("%s: %d, FPS %d" % [species, g["animals"].size(), Engine.get_frames_per_second()])

	# FPS en el mismo lugar con el máximo de animales (Difícil) y sin ninguno.
	var site: Dictionary = good[0]
	var fwd: Vector3 = site["dir"]
	for amount in [1.8, 0.0, 1.8]:
		animals.clear_all()
		animals.density = amount
		main.moto.place_at(site["p"] - fwd * 20.0, atan2(fwd.x, fwd.z))
		main.cam.snap()
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t < 4000:  # Que aparezcan.
			await process_frame
		var frames := 0
		t = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t < 4000:
			await process_frame
			frames += 1
		print("FPS con densidad %.1f: %.0f (%d animales)" % [amount, frames / 4.0, animals.get_animal_count()])
	quit()
