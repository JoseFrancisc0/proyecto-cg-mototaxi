extends SceneTree
## Capturas de la red vial (pendiente 10, fase 2) en el juego real con el terreno del editor:
## cruce de una trocha, cruce de una avenida nueva y las cuadras de un pueblo.
##   Godot --path project -s res://tests/capture_red_vial.gd   (con ventana)
## Guarda output/red_vial/<nombre>.png


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
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/red_vial").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)

	var shots := {}
	var roads := world.get_roads()
	for kind in [0, 2]:
		for road in roads:
			if road["kind"] == kind:
				var path: PackedVector3Array = road["path"]
				shots["cruce_%s" % ["trocha", "", "avenida"][kind]] = [path[0], path[mini(6, path.size() - 1)]]
				break
	var towns := world.generator.last_roads.get_town_centers()
	if towns.size() > 0:
		shots["pueblo"] = [towns[0], towns[0] + Vector3(40, 0, 40)]

	var cam := Camera3D.new()
	cam.far = 3000.0
	root.add_child(cam)
	cam.current = true
	for name in shots:
		var target: Vector3 = shots[name][0]
		var toward: Vector3 = shots[name][1]
		var back := Vector3(target.x - toward.x, 0, target.z - toward.z).normalized()
		if back == Vector3.ZERO:
			back = Vector3.BACK
		var height := 55.0 if name == "pueblo" else 18.0
		var dist := 70.0 if name == "pueblo" else 30.0
		var eye := target + back * dist
		eye.y = world.get_height(eye.x, eye.z) + height
		main.moto.place_at(target + back * 8.0, 0.0)
		cam.global_position = eye
		cam.look_at(target, Vector3.UP)
		for i in 60:
			await process_frame
		root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
		print("%s en %s, FPS %d" % [name, target, Engine.get_frames_per_second()])
	quit()
