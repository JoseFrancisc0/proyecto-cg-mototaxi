extends SceneTree
## Capturas de las viviendas (TerrainHouses) en el juego real: un pueblo por región visto desde
## arriba y desde la calle, y una casa de chacra.
##   Godot --path project -s res://tests/capture_viviendas.gd -- [--editor | --seed=N --region=sierra]  (con ventana)
## Guarda output/casas/<región>_<vista>.png


func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	await process_frame
	await process_frame
	while is_instance_valid(main.loading):
		await process_frame
	var world: TerrainWorld = main.world
	main.moto.use_input = false
	main.race.stop()
	main.hud.visible = false
	main.session.process_mode = Node.PROCESS_MODE_DISABLED  # Sin fin de partida ni reloj.
	var spot: Vector3 = world.get_landmarks()[0]["position"]
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/casas").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	print("Viviendas: %d %s" % [world.houses.houses.size(), world.houses.counts])

	var cam := Camera3D.new()
	cam.far = 3000.0
	root.add_child(cam)
	cam.current = true
	var shots := []
	var done := {}
	for h in world.houses.houses:
		var region: String = StopNames.REGIONS[h["region"]]
		var key: String = region + "_" + h["zone"]
		if done.has(key) or h["zone"] == "afueras":
			continue
		done[key] = true
		var front: Vector3 = Basis(Vector3.UP, h["yaw"]) * Vector3.BACK
		var side := front.cross(Vector3.UP)
		var p: Vector3 = h["position"]
		if h["zone"] == "pueblo":
			shots.append([key + "_arriba", p + front * 30.0 + side * 25.0 + Vector3.UP * 35.0, p])
			shots.append([key + "_calle", p + front * (h["size"].z * 0.5 + 4.5) + side * 16.0 + Vector3.UP * 1.8, p - side * 6.0 + Vector3.UP * 2.0])
		else:
			shots.append([key, p + front * 16.0 + side * 8.0 + Vector3.UP * 4.0, p + Vector3.UP * 2.0])
	for s in shots:
		var eye: Vector3 = s[1]
		eye.y = maxf(eye.y, world.get_height(eye.x, eye.z) + 1.6)
		main.moto.place_at(spot, 0.0)
		cam.global_position = eye
		cam.look_at(s[2], Vector3.UP)
		for i in 45:
			await process_frame
		root.get_texture().get_image().save_png(dir.path_join(s[0] + ".png"))
		print("%s, FPS %d" % [s[0], Engine.get_frames_per_second()])
	# FPS en la calle del primer pueblo, con y sin casas.
	for s in shots:
		if not s[0].ends_with("_calle"):
			continue
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		for visible in [true, false, true]:
			world.houses.visible = visible
			for i in 30:
				await process_frame
			var t0 := Time.get_ticks_msec()
			var frames := 0
			while Time.get_ticks_msec() - t0 < 3000:
				await process_frame
				frames += 1
			print("FPS %s con casas %s: %.0f" % [s[0], visible, frames / 3.0])
		break
	quit()
