extends SceneTree
## Foto de cada modelo de vivienda visto desde +Z (el frente que usa TerrainHouses).
##   Godot --path project -s res://tests/capture_casas_modelos.gd   (con ventana)
## Guarda output/casas/modelo_<nombre>.png


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/casas").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	for model in TerrainHouses.MODELS:
		var info := TerrainHouses.load_model(model)
		var holder := Node3D.new()
		root.add_child(holder)
		for part: Array in info["parts"]:
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = part[1]
			holder.add_child(mi)
		var size: Vector3 = info["size"]
		var r := maxf(size.x, maxf(size.y, size.z))
		for view in [["frente", Vector3(0, 0, 1)], ["lado", Vector3(1, 0, 0)], ["atras", Vector3(0, 0, -1)], ["otro", Vector3(-1, 0, 0)]]:
			var d: Vector3 = view[1]
			cam.position = d * r * 1.7 + Vector3.UP * (size.y * 0.5 + r * 0.25)
			await process_frame
			cam.look_at(Vector3(0, size.y * 0.4, 0), Vector3.UP)
			for i in 6:
				await process_frame
			root.get_texture().get_image().save_png(dir.path_join("modelo_%s_%s.png" % [model["file"].get_basename(), view[0]]))
		print("%s tamaño %s" % [model["file"], size])
		holder.free()
	quit()
