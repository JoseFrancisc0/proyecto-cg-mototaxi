extends SceneTree
## Capturas de los obstáculos de las vías (RoadObstacles) en el juego real: uno de cada tipo,
## visto como desde la mototaxi que se acerca.
##   Godot --path project -s res://tests/capture_obstaculos.gd -- [--seed=N --region=costa]  (con ventana)
## Guarda output/obstaculos/<tipo>.png


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
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/obstaculos").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	print("Obstáculos: %s" % [world.obstacles.counts])

	var cam := Camera3D.new()
	cam.far = 3000.0
	root.add_child(cam)
	cam.current = true
	var done := {}
	for o in world.obstacles.obstacles:
		var name: String = RoadObstacles.KIND_NAMES[o["kind"]] + "_" + StopNames.REGIONS[o["region"]]
		if done.has(name):
			continue
		done[name] = true
		var target: Vector3 = o["position"]
		var back: Vector3 = -o["dir"]
		var eye := target + back * 11.0
		eye.y = world.get_height(eye.x, eye.z) + 2.6
		main.moto.place_at(target + back * 40.0, 0.0)  # Fuera de cuadro.
		cam.global_position = eye
		cam.look_at(target + Vector3.UP * 0.3, Vector3.UP)
		for i in 45:
			await process_frame
		root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
		print("%s en %s, FPS %d" % [name, target, Engine.get_frames_per_second()])
	quit()
